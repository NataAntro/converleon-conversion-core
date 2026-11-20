import Foundation

public struct ConversionRequest: Equatable, Sendable {
    public let sourceURL: URL
    public let format: ConversionFormat

    public init(sourceURL: URL, format: ConversionFormat) {
        self.sourceURL = sourceURL
        self.format = format
    }
}

public struct ConversionBatchFailure: Equatable, Sendable {
    public let sourceURL: URL
    public let format: ConversionFormat
    public let errorType: String
    public let message: String

    init(request: ConversionRequest, error: any Error) {
        sourceURL = request.sourceURL
        format = request.format
        errorType = String(reflecting: type(of: error))
        message = error.localizedDescription
    }
}

public enum ConversionBatchOutcome: Equatable, Sendable {
    case succeeded(ConversionResult)
    case failed(ConversionBatchFailure)
}

extension ConversionCoordinator {
    public func convertBatch(
        _ requests: [ConversionRequest],
        outputDirectory: URL,
        maxConcurrentOperations: Int = 3
    ) async throws -> [ConversionBatchOutcome] {
        guard maxConcurrentOperations > 0 else {
            throw ConversionError.invalidConcurrencyLimit(maxConcurrentOperations)
        }
        guard !requests.isEmpty else { return [] }

        var outcomes = [ConversionBatchOutcome?](repeating: nil, count: requests.count)
        return try await withThrowingTaskGroup(
            of: (Int, ConversionBatchOutcome).self,
            returning: [ConversionBatchOutcome].self
        ) { group in
            var nextIndex = 0
            let initialCount = min(maxConcurrentOperations, requests.count)
            for index in 0..<initialCount {
                let request = requests[index]
                group.addTask {
                    try await self.executeBatchItem(request, index: index, outputDirectory: outputDirectory)
                }
                nextIndex += 1
            }

            while let (index, outcome) = try await group.next() {
                outcomes[index] = outcome
                if nextIndex < requests.count {
                    let index = nextIndex
                    let request = requests[index]
                    group.addTask {
                        try await self.executeBatchItem(
                            request,
                            index: index,
                            outputDirectory: outputDirectory
                        )
                    }
                    nextIndex += 1
                }
            }

            return outcomes.map { outcome in
                guard let outcome else {
                    preconditionFailure("Task group completed without an outcome")
                }
                return outcome
            }
        }
    }

    private func executeBatchItem(
        _ request: ConversionRequest,
        index: Int,
        outputDirectory: URL
    ) async throws -> (Int, ConversionBatchOutcome) {
        do {
            let result = try await convert(
                sourceURL: request.sourceURL,
                to: request.format,
                outputDirectory: outputDirectory
            )
            return (index, .succeeded(result))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return (index, .failed(ConversionBatchFailure(request: request, error: error)))
        }
    }
}
