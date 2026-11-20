import Foundation

public struct UppercaseTextStrategy: ConversionStrategy {
    public let format = ConversionFormat.uppercaseText
    public let supportedKinds: Set<FileKind> = [.plainText]
    public let outputSuffix = "-uppercase"
    public let outputExtension = "txt"

    public init() {}

    public func convert(sourceURL: URL, stagingURL: URL) async throws {
        try Task.checkCancellation()
        guard let text = try String(data: Data(contentsOf: sourceURL), encoding: .utf8) else {
            throw ConversionError.invalidTextEncoding
        }
        try Data(text.uppercased().utf8).write(to: stagingURL, options: .withoutOverwriting)
    }
}
