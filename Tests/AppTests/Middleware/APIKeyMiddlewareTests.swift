import Testing
import VaporTesting
@testable import App

@Suite("APIKeyMiddleware")
struct APIKeyMiddlewareTests {

    private func configure(app: Application, key: String = "secret") throws {
        let protected = app.grouped(APIKeyMiddleware(requiredKey: key))
        try protected.register(collection: ModelsController())
    }

    @Test("blocks missing key")
    func blocksMissingKey() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("allows valid x-api-key header")
    func allowsValidXAPIKey() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            try await app.test(.GET, "/v1/models", headers: ["x-api-key": "secret"]) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("allows valid Bearer token")
    func allowsValidBearerToken() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            var headers = HTTPHeaders()
            headers.add(name: .authorization, value: "Bearer secret")

            try await app.test(.GET, "/v1/models", headers: headers) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("blocks wrong x-api-key")
    func blocksWrongKey() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            try await app.test(.GET, "/v1/models", headers: ["x-api-key": "wrong"]) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("blocks wrong Bearer value")
    func blocksBearerWithWrongValue() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            var headers = HTTPHeaders()
            headers.add(name: .authorization, value: "Bearer wrong")

            try await app.test(.GET, "/v1/models", headers: headers) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("blocks Authorization without Bearer prefix")
    func blocksBearerWithoutPrefix() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            var headers = HTTPHeaders()
            headers.add(name: .authorization, value: "secret")

            try await app.test(.GET, "/v1/models", headers: headers) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("allows lowercase bearer prefix (RFC 7235 case-insensitive scheme)")
    func allowsLowercaseBearerPrefix() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            var headers = HTTPHeaders()
            headers.add(name: .authorization, value: "bearer secret")

            try await app.test(.GET, "/v1/models", headers: headers) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("blocks key that differs only in last byte (timing-safe comparison)")
    func blocksKeyWithLastByteDifference() async throws {
        try await withApp({ app in try configure(app: app, key: "secretA") }) { app in
            try await app.test(.GET, "/v1/models", headers: ["x-api-key": "secretB"]) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }

    @Test("blocks key with same prefix but longer length")
    func blocksKeyWithSamePrefixButLonger() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            try await app.test(.GET, "/v1/models", headers: ["x-api-key": "secretXXX"]) { res async in
                #expect(res.status == .unauthorized)
            }
        }
    }
}
