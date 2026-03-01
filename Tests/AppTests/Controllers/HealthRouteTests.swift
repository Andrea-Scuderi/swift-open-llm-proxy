import Testing
import Vapor
import VaporTesting
@testable import App

@Suite("Health route")
struct HealthRouteTests {

    @Test("GET /health returns 200 OK")
    func returnsOK() async throws {
        try await withApp({ app in
            app.get("health") { _ in HTTPStatus.ok }
        }) { app in
            try await app.test(.GET, "/health") { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("GET /health returns empty body")
    func returnsEmptyBody() async throws {
        try await withApp({ app in
            app.get("health") { _ in HTTPStatus.ok }
        }) { app in
            try await app.test(.GET, "/health") { res async in
                #expect(res.body.readableBytes == 0)
            }
        }
    }

    @Test("GET /health does not require authentication")
    func noAuthRequired() async throws {
        try await withApp({ app in
            app.grouped(APIKeyMiddleware(requiredKey: "secret")).get("protected") { _ in HTTPStatus.ok }
            app.get("health") { _ in HTTPStatus.ok }
        }) { app in
            // No x-api-key header — health must still return 200, not 401.
            try await app.test(.GET, "/health") { res async in
                #expect(res.status == .ok)
            }
        }
    }
}
