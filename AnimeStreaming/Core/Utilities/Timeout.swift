import Foundation

enum TimeoutError: Error, Equatable, Sendable {
    case timedOut
}

func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError.timedOut
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else {
            throw TimeoutError.timedOut
        }
        return result
    }
}
