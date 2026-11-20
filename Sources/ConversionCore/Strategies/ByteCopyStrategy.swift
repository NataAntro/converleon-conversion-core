import Foundation

public struct ByteCopyStrategy: ConversionStrategy {
    public let format = ConversionFormat.byteCopy
    public let supportedKinds: Set<FileKind> = [.plainText, .json, .binary]
    public let outputSuffix = "-copy"
    public let outputExtension = "dat"

    public init() {}

    public func convert(sourceURL: URL, stagingURL: URL) async throws {
        try Task.checkCancellation()
        try FileManager.default.copyItem(at: sourceURL, to: stagingURL)
    }
}
