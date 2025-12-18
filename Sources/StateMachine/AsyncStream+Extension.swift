import Foundation

public extension AsyncStream {
    
    static func single(
        priority: TaskPriority? = nil,
        _ operation: @Sendable @escaping () async -> Element
    ) -> Self {
        Self.init { observer in
            let task = Task(priority: priority) {
                let value = await operation()
                try Task.checkCancellation()
                observer.yield(value)
                observer.finish()
            }
            observer.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
}
