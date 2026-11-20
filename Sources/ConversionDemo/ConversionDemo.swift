import ConversionCore
import Foundation

@main
struct ConversionDemo {
    static func main() async {
        do {
            let outputDirectory = try resolveOutputDirectory()
            let inputDirectory = outputDirectory.appendingPathComponent("reference-input", isDirectory: true)
            try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)

            let note = inputDirectory.appendingPathComponent("weekly-note.txt")
            let digest = inputDirectory.appendingPathComponent("digest.json")
            let payload = inputDirectory.appendingPathComponent("payload.bin")
            try Data("swift concurrency keeps file jobs predictable\n".utf8).write(to: note)
            try Data(#"{"items":2,"topic":"weekly digest"}"#.utf8).write(to: digest)
            try Data([0x43, 0x4F, 0x52, 0x45]).write(to: payload)

            let coordinator = ConversionCoordinator()
            async let textResult = coordinator.convert(
                sourceURL: note,
                to: .uppercaseText,
                outputDirectory: outputDirectory
            )
            async let jsonResult = coordinator.convert(
                sourceURL: digest,
                to: .prettyJSON,
                outputDirectory: outputDirectory
            )
            async let copyResult = coordinator.convert(
                sourceURL: payload,
                to: .byteCopy,
                outputDirectory: outputDirectory
            )

            let results = try await [textResult, jsonResult, copyResult]
            print("Conversion run завершён. Созданы результаты:")
            for result in results {
                print("- \(result.outputURL.path)")
            }
        } catch {
            fputs("Ошибка conversion run: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    private static func resolveOutputDirectory() throws -> URL {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true).standardizedFileURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("demo-output", isDirectory: true)
    }
}
