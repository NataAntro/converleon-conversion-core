import Foundation
import UniformTypeIdentifiers

public enum FileKind: String, CaseIterable, Sendable {
    case plainText
    case json
    case binary
    case unknown
}

public struct FileTypeDetector: Sendable {
    public init() {}

    public func detect(_ url: URL) throws -> FileKind {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey])
        } catch {
            throw ConversionError.sourceDoesNotExist(url)
        }

        guard values.isRegularFile == true else {
            throw ConversionError.sourceIsNotARegularFile(url)
        }

        let fileExtension = url.pathExtension.lowercased()
        switch fileExtension {
        case "json":
            return .json
        case "txt", "md", "csv":
            return .plainText
        case "bin", "dat":
            return .binary
        default:
            break
        }

        guard let type = UTType(filenameExtension: fileExtension) else {
            return .unknown
        }
        guard !type.isDynamic else {
            return .unknown
        }
        if type.conforms(to: .json) {
            return .json
        }
        if type.conforms(to: .text) {
            return .plainText
        }
        if type.conforms(to: .data) {
            return .binary
        }
        return .unknown
    }
}
