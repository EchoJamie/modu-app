import Foundation

enum CancellableWorker {
    static func run<Value: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let worker = Task.detached(priority: priority, operation: operation)
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
