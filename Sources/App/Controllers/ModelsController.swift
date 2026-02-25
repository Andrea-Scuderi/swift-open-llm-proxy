import Vapor

struct ModelsController: RouteCollection {
    private let overrideListable: (any FoundationModelListable)?

    init(foundationModelListable: (any FoundationModelListable)? = nil) {
        self.overrideListable = foundationModelListable
    }

    func boot(routes: RoutesBuilder) throws {
        routes.get("v1", "models", use: listModels)
    }

    @Sendable
    func listModels(req: Request) async throws -> ModelListResponse {
        let now = Int(Date().timeIntervalSince1970)
        let service = overrideListable ?? req.application.optionalBedrockService
        guard let service else { return fallbackModelList(created: now) }
        do {
            let foundationModels = try await service.listFoundationModels()
            let models: [ModelObject] = foundationModels.compactMap { model in
                guard model.isActive else { return nil }
                let displayID = model.modelName ?? model.modelId
                let ownedBy = (model.providerName ?? Self.ownedBy(for: model.modelId)).lowercased()
                return ModelObject(id: displayID, object: "model", created: now, ownedBy: ownedBy)
            }
            guard !models.isEmpty else { return fallbackModelList(created: now) }
            return ModelListResponse(object: "list", data: models)
        } catch {
            req.logger.warning("listFoundationModels failed, falling back: \(error)")
            return fallbackModelList(created: now)
        }
    }

    // MARK: - ownedBy derivation

    /// Derives the provider name from a Bedrock model ID.
    /// Handles both plain IDs (`anthropic.claude-…`, `amazon.nova-…`) and
    /// cross-region inference profile IDs (`us.anthropic.…`, `eu.amazon.…`).
    static func ownedBy(for modelId: String) -> String {
        let parts = modelId.split(separator: ".", maxSplits: 2)
        let first = parts.first.map(String.init) ?? ""
        let regionPrefixes: Set<String> = ["us", "eu", "ap"]
        if regionPrefixes.contains(first), parts.count >= 2 {
            return String(parts[1])
        }
        return first
    }

    // MARK: - Fallback model list

    private func fallbackModelList(created: Int) -> ModelListResponse {
        let models = ModelMapper.modelNameToBedrockID.map { (name, bedrockID) in
            ModelObject(id: name, object: "model", created: created, ownedBy: Self.ownedBy(for: bedrockID))
        }.sorted { $0.id < $1.id }
        return ModelListResponse(object: "list", data: models)
    }
}
