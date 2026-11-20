import Foundation
import XCTest

@testable import ConversionCore

final class OutputURLAllocatorTests: XCTestCase {
    func testSkipsExistingFileAndReleasedReservationBecomesReusable() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        _ = try root.write("report.txt", data: Data("occupied".utf8))

        let allocator = OutputURLAllocator()
        let first = try await allocator.reserve(
            directory: root.url,
            baseName: "report",
            fileExtension: "txt"
        )
        XCTAssertEqual(first.url.lastPathComponent, "report-2.txt")

        let second = try await allocator.reserve(
            directory: root.url,
            baseName: "report",
            fileExtension: "txt"
        )
        XCTAssertEqual(second.url.lastPathComponent, "report-3.txt")

        await allocator.release(first)
        let reused = try await allocator.reserve(
            directory: root.url,
            baseName: "report",
            fileExtension: "txt"
        )
        XCTAssertEqual(reused.url.lastPathComponent, "report-2.txt")
    }

    func testConcurrentReservationsAreUniqueAndStayInsideDirectory() async throws {
        let root = try TestDirectory()
        defer { root.remove() }
        let allocator = OutputURLAllocator()

        let reservations = try await withThrowingTaskGroup(of: OutputReservation.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await allocator.reserve(
                        directory: root.url,
                        baseName: "../unsafe name",
                        fileExtension: ".TXT"
                    )
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        XCTAssertEqual(Set(reservations.map(\.url)).count, 20)
        XCTAssertTrue(
            reservations.allSatisfy {
                $0.url.deletingLastPathComponent().standardizedFileURL == root.url.standardizedFileURL
            })
    }
}
