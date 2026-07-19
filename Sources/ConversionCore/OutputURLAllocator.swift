import Foundation

public struct OutputReservation: Hashable, Sendable {
    public let id: UUID
    public let url: URL

    fileprivate init(id: UUID, url: URL) {
        self.id = id
        self.url = url
    }
}

public actor OutputURLAllocator {
    private var reservedPaths: [String: UUID] = [:]

    public init() {}

    public func reserve(
        directory: URL,
        baseName: String,
        fileExtension: String
    ) throws -> OutputReservation {
        let safeBaseName = Self.sanitize(baseName)
        let safeExtension = Self.sanitizeExtension(fileExtension)

        for sequence in 1...10_000 {
            let suffix = sequence == 1 ? "" : "-\(sequence)"
            let fileName = "\(safeBaseName)\(suffix).\(safeExtension)"
            let candidate = directory.appendingPathComponent(fileName, isDirectory: false)
            let path = candidate.standardizedFileURL.path

            guard reservedPaths[path] == nil,
                !FileManager.default.fileExists(atPath: path)
            else {
                continue
            }

            let id = UUID()
            reservedPaths[path] = id
            return OutputReservation(id: id, url: candidate)
        }

        let fallbackName = "\(safeBaseName)-\(UUID().uuidString.lowercased()).\(safeExtension)"
        let fallback = directory.appendingPathComponent(fallbackName, isDirectory: false)
        let id = UUID()
        reservedPaths[fallback.standardizedFileURL.path] = id
        return OutputReservation(id: id, url: fallback)
    }

    public func release(_ reservation: OutputReservation) {
        let path = reservation.url.standardizedFileURL.path
        guard reservedPaths[path] == reservation.id else { return }
        reservedPaths[path] = nil
    }

    public func activeReservationCount() -> Int {
        reservedPaths.count
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let normalized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return normalized.isEmpty ? "output" : String(normalized.prefix(80))
    }

    private static func sanitizeExtension(_ value: String) -> String {
        let normalized = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return normalized.isEmpty ? "dat" : String(normalized.prefix(12))
    }
}
