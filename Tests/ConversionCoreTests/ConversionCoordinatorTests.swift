import Foundation
import XCTest

@testable import ConversionCore

final class ConversionCoordinatorTests: XCTestCase {
    func testAvailableFormatsAreDerivedFromDetectedFileKind() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        let text = try root.write("note.txt", data: Data("text".utf8))
        let json = try root.write("config.json", data: Data("{}".utf8))
        let binary = try root.write("payload.bin", data: Data([0x01]))
        let coordinator = ConversionCoordinator()

        let textFormats = try await coordinator.availableFormats(for: text)
        let jsonFormats = try await coordinator.availableFormats(for: json)
        let binaryFormats = try await coordinator.availableFormats(for: binary)

        XCTAssertEqual(textFormats, [.uppercaseText, .byteCopy])
        XCTAssertEqual(jsonFormats, [.prettyJSON, .byteCopy])
        XCTAssertEqual(binaryFormats, [.byteCopy])
    }

    func testTextAndJSONStrategiesProduceExpectedFiles() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        let source = root.url.appendingPathComponent("source", isDirectory: true)
        let output = root.url.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let text = source.appendingPathComponent("note.txt")
        try Data("Swift and files".utf8).write(to: text)
        let json = source.appendingPathComponent("config.json")
        try Data(#"{"z":1,"a":2}"#.utf8).write(to: json)

        let coordinator = ConversionCoordinator()
        let textResult = try await coordinator.convert(
            sourceURL: text,
            to: .uppercaseText,
            outputDirectory: output
        )
        let jsonResult = try await coordinator.convert(
            sourceURL: json,
            to: .prettyJSON,
            outputDirectory: output
        )

        XCTAssertEqual(try String(contentsOf: textResult.outputURL, encoding: .utf8), "SWIFT AND FILES")
        let pretty = try String(contentsOf: jsonResult.outputURL, encoding: .utf8)
        XCTAssertTrue(pretty.contains("\n"))
        let aIndex = try XCTUnwrap(pretty.range(of: "\"a\""))
        let zIndex = try XCTUnwrap(pretty.range(of: "\"z\""))
        XCTAssertTrue(aIndex.lowerBound < zIndex.lowerBound)
    }

    func testConcurrentConversionsNeverOverwriteOutputs() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        let source = try root.write("report.txt", data: Data("parallel".utf8))
        let coordinator = ConversionCoordinator()

        let outputs = try await withThrowingTaskGroup(of: URL.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    let result = try await coordinator.convert(
                        sourceURL: source,
                        to: .uppercaseText,
                        outputDirectory: root.url
                    )
                    return result.outputURL
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        XCTAssertEqual(Set(outputs).count, 12)
        XCTAssertTrue(outputs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(outputs.contains { $0.lastPathComponent == "report-uppercase.txt" })
        XCTAssertTrue(outputs.contains { $0.lastPathComponent == "report-uppercase-12.txt" })
    }

    func testExistingOutputIsPreserved() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        let source = try root.write("memo.txt", data: Data("new".utf8))
        let existing = try root.write("memo-uppercase.txt", data: Data("keep".utf8))

        let result = try await ConversionCoordinator().convert(
            sourceURL: source,
            to: .uppercaseText,
            outputDirectory: root.url
        )

        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "keep")
        XCTAssertEqual(result.outputURL.lastPathComponent, "memo-uppercase-2.txt")
    }

    func testFailureRemovesPartialStagingFileAndFinalOutput() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        let source = try root.write("memo.txt", data: Data("source".utf8))
        let coordinator = ConversionCoordinator(strategies: [PartialFailureStrategy()])

        do {
            _ = try await coordinator.convert(
                sourceURL: source,
                to: .uppercaseText,
                outputDirectory: root.url
            )
            XCTFail("Expected strategy failure")
        } catch is ExpectedStrategyFailure {
            // Ожидаемая ошибка тестового adapter.
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: root.url.path)
        XCTAssertFalse(files.contains { $0.hasPrefix(".conversion-stage-") })
        XCTAssertFalse(files.contains("memo-uppercase.txt"))
    }

    func testUnsupportedStrategyReturnsTypedError() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        let source = try root.write("memo.txt", data: Data("source".utf8))

        do {
            _ = try await ConversionCoordinator().convert(
                sourceURL: source,
                to: .prettyJSON,
                outputDirectory: root.url
            )
            XCTFail("Expected unsupported conversion")
        } catch let error as ConversionError {
            XCTAssertEqual(error, .unsupportedConversion(format: .prettyJSON, kind: .plainText))
        }
    }

    func testDuplicateStrategyReturnsTypedConfigurationError() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        let source = try root.write("memo.txt", data: Data("source".utf8))
        let coordinator = ConversionCoordinator(
            strategies: [UppercaseTextStrategy(), PartialFailureStrategy()]
        )

        do {
            _ = try await coordinator.convert(
                sourceURL: source,
                to: .uppercaseText,
                outputDirectory: root.url
            )
            XCTFail("Expected duplicate strategy error")
        } catch let error as ConversionError {
            XCTAssertEqual(error, .duplicateStrategy(format: .uppercaseText))
        }
    }

    func testCancellationRemovesStagingFileAndReleasesReservation() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        let source = try root.write("memo.txt", data: Data("source".utf8))
        let allocator = OutputURLAllocator()
        let coordinator = ConversionCoordinator(
            allocator: allocator,
            strategies: [CancellableStrategy()]
        )

        let conversion = Task {
            try await coordinator.convert(
                sourceURL: source,
                to: .uppercaseText,
                outputDirectory: root.url
            )
        }
        for _ in 0..<100 {
            let files = try FileManager.default.contentsOfDirectory(atPath: root.url.path)
            if files.contains(where: { $0.hasPrefix(".conversion-stage-") }) {
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        conversion.cancel()

        do {
            _ = try await conversion.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Ожидаемая отмена задачи.
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: root.url.path)
        XCTAssertFalse(files.contains { $0.hasPrefix(".conversion-stage-") })
        XCTAssertFalse(files.contains("memo-uppercase.txt"))
        let activeReservations = await allocator.activeReservationCount()
        XCTAssertEqual(activeReservations, 0)
    }

    func testExternalOutputConflictPreservesForeignFileAndCleansStaging() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        let source = try root.write("memo.txt", data: Data("source".utf8))
        let allocator = OutputURLAllocator()
        let coordinator = ConversionCoordinator(
            allocator: allocator,
            strategies: [ExternalConflictStrategy()]
        )

        do {
            _ = try await coordinator.convert(
                sourceURL: source,
                to: .uppercaseText,
                outputDirectory: root.url
            )
            XCTFail("Expected output conflict")
        } catch let error as ConversionError {
            XCTAssertEqual(
                error,
                .outputAppearedDuringConversion(
                    root.url.appendingPathComponent("memo-uppercase.txt")
                )
            )
        }

        let external = root.url.appendingPathComponent("memo-uppercase.txt")
        XCTAssertEqual(try String(contentsOf: external, encoding: .utf8), "external")
        let files = try FileManager.default.contentsOfDirectory(atPath: root.url.path)
        XCTAssertFalse(files.contains { $0.hasPrefix(".conversion-stage-") })
        let activeReservations = await allocator.activeReservationCount()
        XCTAssertEqual(activeReservations, 0)
    }

    func testBatchBoundsConcurrencyPreservesOrderAndIsolatesItemFailure() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        let sources = try [
            root.write("first.txt", data: Data("one".utf8)),
            root.write("broken.txt", data: Data("two".utf8)),
            root.write("third.txt", data: Data("three".utf8)),
        ]
        let probe = ConcurrencyProbe()
        let coordinator = ConversionCoordinator(strategies: [BatchProbeStrategy(probe: probe)])

        let outcomes = try await coordinator.convertBatch(
            sources.map { ConversionRequest(sourceURL: $0, format: .uppercaseText) },
            outputDirectory: root.url,
            maxConcurrentOperations: 2
        )

        let maximumActive = await probe.maximumActive
        XCTAssertEqual(maximumActive, 2)
        XCTAssertEqual(outcomes.count, 3)
        guard case .succeeded(let first) = outcomes[0] else {
            return XCTFail("First item must succeed")
        }
        guard case .failed(let second) = outcomes[1] else {
            return XCTFail("Second item must fail")
        }
        guard case .succeeded(let third) = outcomes[2] else {
            return XCTFail("Third item must succeed")
        }
        XCTAssertEqual(first.sourceURL.lastPathComponent, "first.txt")
        XCTAssertEqual(second.sourceURL.lastPathComponent, "broken.txt")
        XCTAssertEqual(third.sourceURL.lastPathComponent, "third.txt")
    }

    func testBatchCancellationCleansEveryActiveOperation() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        let sources = try (1...4).map { index in
            try root.write("item-\(index).txt", data: Data("source".utf8))
        }
        let allocator = OutputURLAllocator()
        let coordinator = ConversionCoordinator(
            allocator: allocator,
            strategies: [CancellableStrategy()]
        )
        let batch = Task {
            try await coordinator.convertBatch(
                sources.map { ConversionRequest(sourceURL: $0, format: .uppercaseText) },
                outputDirectory: root.url,
                maxConcurrentOperations: 2
            )
        }

        for _ in 0..<100 {
            let files = try FileManager.default.contentsOfDirectory(atPath: root.url.path)
            if files.filter({ $0.hasPrefix(".conversion-stage-") }).count == 2 {
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        batch.cancel()

        do {
            _ = try await batch.value
            XCTFail("Expected batch cancellation")
        } catch is CancellationError {
            // Ожидаемая отмена всей группы.
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: root.url.path)
        XCTAssertFalse(files.contains { $0.hasPrefix(".conversion-stage-") })
        XCTAssertFalse(files.contains { $0.hasSuffix("-uppercase.txt") })
        let activeReservations = await allocator.activeReservationCount()
        XCTAssertEqual(activeReservations, 0)
    }

    func testTypedErrorsExposeActionableDescriptions() {
        let source = URL(fileURLWithPath: "/tmp/source.txt")
        let errors: [ConversionError] = [
            .invalidConcurrencyLimit(0),
            .duplicateStrategy(format: .uppercaseText),
            .sourceDoesNotExist(source),
            .sourceIsNotARegularFile(source),
            .unsupportedFileType("unknown"),
            .unsupportedConversion(format: .prettyJSON, kind: .plainText),
            .invalidTextEncoding,
            .invalidJSON,
            .strategyDidNotProduceOutput,
            .outputAppearedDuringConversion(source),
        ]

        XCTAssertTrue(
            errors.allSatisfy { error in
                guard let description = error.errorDescription else { return false }
                return !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
    }
}

private struct ExpectedStrategyFailure: Error {}

private struct PartialFailureStrategy: ConversionStrategy {
    let format = ConversionFormat.uppercaseText
    let supportedKinds: Set<FileKind> = [.plainText]
    let outputSuffix = "-uppercase"
    let outputExtension = "txt"

    func convert(sourceURL: URL, stagingURL: URL) async throws {
        try Data("partial".utf8).write(to: stagingURL)
        throw ExpectedStrategyFailure()
    }
}

private struct CancellableStrategy: ConversionStrategy {
    let format = ConversionFormat.uppercaseText
    let supportedKinds: Set<FileKind> = [.plainText]
    let outputSuffix = "-uppercase"
    let outputExtension = "txt"

    func convert(sourceURL: URL, stagingURL: URL) async throws {
        _ = sourceURL
        try Data("partial".utf8).write(to: stagingURL)
        try await Task.sleep(for: .seconds(30))
    }
}

private struct ExternalConflictStrategy: ConversionStrategy {
    let format = ConversionFormat.uppercaseText
    let supportedKinds: Set<FileKind> = [.plainText]
    let outputSuffix = "-uppercase"
    let outputExtension = "txt"

    func convert(sourceURL: URL, stagingURL: URL) async throws {
        _ = sourceURL
        try Data("converted".utf8).write(to: stagingURL)
        let external = stagingURL.deletingLastPathComponent()
            .appendingPathComponent("memo-uppercase.txt")
        try Data("external".utf8).write(to: external)
    }
}

private actor ConcurrencyProbe {
    private(set) var active = 0
    private(set) var maximumActive = 0

    func begin() {
        active += 1
        maximumActive = max(maximumActive, active)
    }

    func end() {
        active -= 1
    }
}

private struct BatchProbeStrategy: ConversionStrategy {
    let format = ConversionFormat.uppercaseText
    let supportedKinds: Set<FileKind> = [.plainText]
    let outputSuffix = "-uppercase"
    let outputExtension = "txt"
    let probe: ConcurrencyProbe

    func convert(sourceURL: URL, stagingURL: URL) async throws {
        await probe.begin()
        do {
            try await Task.sleep(for: .milliseconds(10))
            if sourceURL.lastPathComponent == "broken.txt" {
                throw ExpectedStrategyFailure()
            }
            try Data("converted".utf8).write(to: stagingURL)
            await probe.end()
        } catch {
            await probe.end()
            throw error
        }
    }
}
