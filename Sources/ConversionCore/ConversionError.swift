import Foundation

public enum ConversionError: Error, Equatable, LocalizedError, Sendable {
    case invalidConcurrencyLimit(Int)
    case sourceDoesNotExist(URL)
    case sourceIsNotARegularFile(URL)
    case unsupportedFileType(String)
    case unsupportedConversion(format: ConversionFormat, kind: FileKind)
    case invalidTextEncoding
    case invalidJSON
    case strategyDidNotProduceOutput
    case outputAppearedDuringConversion(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidConcurrencyLimit(let value):
            "Concurrency limit must be positive, got \(value)."
        case .sourceDoesNotExist(let url):
            "Исходный файл не найден: \(url.lastPathComponent)"
        case .sourceIsNotARegularFile(let url):
            "Источник не является обычным файлом: \(url.lastPathComponent)"
        case .unsupportedFileType(let fileExtension):
            "Тип файла не поддерживается: \(fileExtension.isEmpty ? "без расширения" : fileExtension)"
        case .unsupportedConversion(let format, let kind):
            "Формат \(format.rawValue) не поддерживает тип \(kind.rawValue)"
        case .invalidTextEncoding:
            "Ожидался текст в UTF-8"
        case .invalidJSON:
            "Ожидался корректный JSON"
        case .strategyDidNotProduceOutput:
            "Стратегия не создала временный результат"
        case .outputAppearedDuringConversion(let url):
            "Путь результата был занят внешним процессом: \(url.lastPathComponent)"
        }
    }
}
