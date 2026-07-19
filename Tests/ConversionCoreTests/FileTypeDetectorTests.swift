import Foundation
import XCTest

@testable import ConversionCore

final class FileTypeDetectorTests: XCTestCase {
    func testDetectsTextJSONBinaryAndUnknownExtensions() throws {
        let root = try TestDirectory()
        defer { root.remove() }

        let text = try root.write("note.txt", data: Data("hello".utf8))
        let json = try root.write("data.json", data: Data("{}".utf8))
        let binary = try root.write("blob.bin", data: Data([0, 1, 2]))
        let unknown = try root.write("mystery.demo-unknown", data: Data([3]))

        let detector = FileTypeDetector()
        XCTAssertEqual(try detector.detect(text), .plainText)
        XCTAssertEqual(try detector.detect(json), .json)
        XCTAssertEqual(try detector.detect(binary), .binary)
        XCTAssertEqual(try detector.detect(unknown), .unknown)
    }

    func testRejectsMissingSourceAndDirectory() throws {
        let root = try TestDirectory()
        defer { root.remove() }

        XCTAssertThrowsError(try FileTypeDetector().detect(root.url.appendingPathComponent("missing.txt")))
        XCTAssertThrowsError(try FileTypeDetector().detect(root.url))
    }
}
