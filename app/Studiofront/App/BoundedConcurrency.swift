/// Runs `operation` for every element with at most `limit` in flight, handing
/// each result to `onResult` on the main actor as soon as it lands.
///
/// A sliding window rather than fixed-size batches: a new request starts the
/// moment any one finishes, so one slow project never holds back the rest of
/// its batch. Stops starting new work once the calling task is cancelled.
///
/// `@MainActor` rather than an `isolated` parameter: a task-group body only
/// inherits an `isolated` parameter's actor if it captures it, so with one
/// `onResult` silently ran on the global executor.
@MainActor
func forEachConcurrently<Element: Sendable, Output: Sendable>(
    _ elements: [Element],
    limit: Int,
    operation: @escaping @Sendable (Element) async -> Output,
    onResult: (Output) -> Void
) async {
    await withTaskGroup(of: Output.self) { group in
        var pending = elements.makeIterator()
        for _ in 0..<max(1, limit) {
            guard let element = pending.next() else { break }
            group.addTask { await operation(element) }
        }
        for await output in group {
            onResult(output)
            if !Task.isCancelled, let element = pending.next() {
                group.addTask { await operation(element) }
            }
        }
    }
}
