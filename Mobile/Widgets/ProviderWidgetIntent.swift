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
        WidgetDataAccess.providers(in: WidgetDataAccess.cachedSnapshot()).map {
            ProviderWidgetEntity(id: $0.provider.providerID, name: $0.provider.displayName)
        }
    }
}

/// One metric a widget can lead with. Only metrics kept visible in the app are offered, so the widget
/// configuration and the Today screen never disagree.
struct ProviderMetricWidgetEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Metric")
    static let defaultQuery = ProviderMetricWidgetEntityQuery()

    var id: String
    var name: String
    var providerName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(providerName)")
    }
}

struct ProviderMetricWidgetEntityQuery: EntityQuery, EnumerableEntityQuery {
    /// Narrows the list to the provider already chosen in the same configuration. Without a provider the
    /// query still answers with every visible metric, so an existing choice keeps resolving.
    @IntentParameterDependency<ProviderWidgetIntent>(\.$provider)
    var configuration

    func entities(for identifiers: [String]) async throws -> [ProviderMetricWidgetEntity] {
        try await allEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProviderMetricWidgetEntity] { try await allEntities() }

    func allEntities() async throws -> [ProviderMetricWidgetEntity] {
        WidgetDataAccess.visibleMetrics(providerID: configuration?.provider.id).map { entry in
            ProviderMetricWidgetEntity(
                id: entry.metric.id,
                name: entry.metric.label,
                providerName: entry.provider.displayName
            )
        }
    }
}

struct ProviderWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Provider Usage"
    static let description = IntentDescription("Choose the provider and metric shown in this widget.")

    @Parameter(title: "Provider")
    var provider: ProviderWidgetEntity?

    @Parameter(title: "Metric")
    var metric: ProviderMetricWidgetEntity?
}
