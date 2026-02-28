import VaporTesting

/// Runs `test` with a freshly-created Application, ensuring `asyncShutdown`
/// is always awaited (even if the test throws).
///
/// Use this instead of the `defer { Task { try await app.asyncShutdown() } }` anti-pattern.
/// The fire-and-forget Task form does not await the shutdown, which can accumulate NIO
/// event loops on macOS and cause CI hangs when many tests run concurrently.
@discardableResult
func withApp<T>(
    _ configure: (Application) throws -> Void,
    _ test: (Application) async throws -> T
) async throws -> T {
    let app = try await Application.make(.testing)
    try configure(app)
    do {
        let result = try await test(app)
        try await app.asyncShutdown()
        return result
    } catch {
        try await app.asyncShutdown()
        throw error
    }
}
