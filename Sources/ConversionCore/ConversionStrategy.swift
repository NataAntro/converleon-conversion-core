import Foundation

public enum ConversionFormat: String, CaseIterable, Sendable {
    case uppercaseText = "uppercase-text"
    case prettyJSON = "pretty-json"
    case byteCopy = "byte-copy"
}

public protocol ConversionStrategy: Sendable {
    var format: ConversionFormat { get }
    var supportedKinds: Set<FileKind> { get }
    var outputSuffix: String { get }
    var outputExtension: String { get }

    func convert(sourceURL: URL, stagingURL: URL) async throws
}
