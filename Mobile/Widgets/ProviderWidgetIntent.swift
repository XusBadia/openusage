import AppIntents
import OpenUsageMobileCore

struct ProviderWidgetEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Provider")
    static let defaultQuery = ProviderWidgetEntityQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ProviderWidgetEntityQuery: EntityQuery, EnumerableEntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProviderWidgetEntity] {
        entities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProviderWidgetEntity] { entities() }
    func allEntities() async throws -> [ProviderWidgetEntity] { entities() }

    private func entities() -> [ProviderWidgetEntity] {
        WidgetDataAccess.providers().map {
            ProviderWidgetEntity(id: $0.provider.providerID, name: $0.provider.displayName)
        }
    }
}

struct ProviderWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Provider Usage"
    static let description = IntentDescription("Choose the provider shown in this widget.")

    @Parameter(title: "Provider")
    var provider: ProviderWidgetEntity?
}
