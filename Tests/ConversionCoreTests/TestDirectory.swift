import Foundation

struct TestDirectory: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("conversion-core-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ name: String, data: Data) throws -> URL {
        let fileURL = url.appendingPathComponent(name, isDirectory: false)
        try data.write(to: fileURL)
        return fileURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
