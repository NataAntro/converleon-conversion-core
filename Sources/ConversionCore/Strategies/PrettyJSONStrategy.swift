import Foundation

public struct PrettyJSONStrategy: ConversionStrategy {
    public let format = ConversionFormat.prettyJSON
    public let supportedKinds: Set<FileKind> = [.json]
    public let outputSuffix = "-pretty"
    public let outputExtension = "json"

    public init() {}

    public func convert(sourceURL: URL, stagingURL: URL) async throws {
        try Task.checkCancellation()
        let source = try Data(contentsOf: sourceURL)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: source)
        } catch {
            throw ConversionError.invalidJSON
        }
        let output = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: stagingURL, options: .withoutOverwriting)
    }
}
