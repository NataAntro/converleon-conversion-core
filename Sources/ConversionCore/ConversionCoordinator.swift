import Foundation

public struct ConversionResult: Equatable, Sendable {
    public let sourceURL: URL
    public let outputURL: URL
    public let format: ConversionFormat

    public init(sourceURL: URL, outputURL: URL, format: ConversionFormat) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.format = format
    }
}

public actor ConversionCoordinator {
    private let detector: FileTypeDetector
    private let allocator: OutputURLAllocator
    private let strategies: [ConversionFormat: any ConversionStrategy]
    private let configurationError: ConversionError?

    public init(
        detector: FileTypeDetector = FileTypeDetector(),
        allocator: OutputURLAllocator = OutputURLAllocator(),
        strategies: [any ConversionStrategy] = [
            UppercaseTextStrategy(),
            PrettyJSONStrategy(),
            ByteCopyStrategy(),
        ]
    ) {
        self.detector = detector
        self.allocator = allocator
        var strategyMap: [ConversionFormat: any ConversionStrategy] = [:]
        var duplicateFormat: ConversionFormat?
        for strategy in strategies {
            if strategyMap.updateValue(strategy, forKey: strategy.format) != nil {
                duplicateFormat = duplicateFormat ?? strategy.format
            }
        }
        self.strategies = strategyMap
        self.configurationError = duplicateFormat.map { .duplicateStrategy(format: $0) }
    }

    public func availableFormats(for sourceURL: URL) throws -> [ConversionFormat] {
        if let configurationError { throw configurationError }
        let kind = try detector.detect(sourceURL)
        guard kind != .unknown else { return [] }

        return ConversionFormat.allCases.filter { format in
            strategies[format]?.supportedKinds.contains(kind) == true
        }
    }

    public func convert(
        sourceURL: URL,
        to format: ConversionFormat,
        outputDirectory: URL
    ) async throws -> ConversionResult {
        try Task.checkCancellation()
        if let configurationError { throw configurationError }
        let kind = try detector.detect(sourceURL)
        guard kind != .unknown else {
            throw ConversionError.unsupportedFileType(sourceURL.pathExtension)
        }
        guard let strategy = strategies[format], strategy.supportedKinds.contains(kind) else {
            throw ConversionError.unsupportedConversion(format: format, kind: kind)
        }

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let sourceStem = sourceURL.deletingPathExtension().lastPathComponent
        let reservation = try await allocator.reserve(
            directory: outputDirectory,
            baseName: sourceStem + strategy.outputSuffix,
            fileExtension: strategy.outputExtension
        )
        let stagingURL = outputDirectory.appendingPathComponent(
            ".conversion-stage-\(UUID().uuidString).tmp",
            isDirectory: false
        )

        do {
            try await strategy.convert(sourceURL: sourceURL, stagingURL: stagingURL)
            try Task.checkCancellation()
            guard FileManager.default.fileExists(atPath: stagingURL.path) else {
                throw ConversionError.strategyDidNotProduceOutput
            }
            guard !FileManager.default.fileExists(atPath: reservation.url.path) else {
                throw ConversionError.outputAppearedDuringConversion(reservation.url)
            }

            try FileManager.default.moveItem(at: stagingURL, to: reservation.url)
            await allocator.release(reservation)
            return ConversionResult(
                sourceURL: sourceURL,
                outputURL: reservation.url,
                format: format
            )
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            await allocator.release(reservation)
            throw error
        }
    }
}
