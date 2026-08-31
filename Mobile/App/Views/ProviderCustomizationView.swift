import OpenUsageMobileCore
import SwiftUI

/// Chooses which providers appear, in what order, and opens each provider's own metric screen.
/// Everything here is stored in the App Group, so the app and both widgets follow the same choices.
struct ProviderCustomizationView: View {
    @Environment(MobileDashboardStore.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(store.customizableProviders) { source in
                    NavigationLink {
                        ProviderMetricCustomizationView(source: source)
                    } label: {
                        providerRow(source)
                    }
                }
                .onMove(perform: store.moveProviders)
            } header: {
                Text("Providers")
            } footer: {
                Text("Tap a provider to choose its metrics. Tap Edit to reorder. Hidden providers stay synced and can be shown again at any time.")
            }

            if store.providerListIsCustomized {
                Section {
                    Button("Reset Every Provider", action: store.resetProviderDisplaySettings)
                } footer: {
                    Text("Shows every provider and metric again, and restores the order published by your Mac.")
                }
            }
        }
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    private func providerRow(_ source: ResolvedMobileProvider) -> some View {
        let provider = source.provider
        return HStack(spacing: 12) {
            ProviderIconView(providerID: provider.providerID, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.body.weight(.medium))
                Text(summary(for: provider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private func summary(for provider: MobileProviderSnapshot) -> String {
        guard !store.providerDisplaySettings.hiddenProviderIDs.contains(provider.providerID) else {
            return "Hidden"
        }
        let total = store.customizableMetrics(for: provider).count
        let visible = store.providerDisplaySettings.visibleMetrics(for: provider).count
        let detail = store.metricSettings(for: provider.providerID).detail.title
        guard total > 0 else { return "No metrics published" }
        return "\(visible) of \(total) metrics · \(detail)"
    }
}

/// Chooses what one provider shows: whether it appears at all, which of its metrics are visible, in what
/// order, and how many of them fit on the Today card.
struct ProviderMetricCustomizationView: View {
    let source: ResolvedMobileProvider
    @Environment(MobileDashboardStore.self) private var store

    private var provider: MobileProviderSnapshot { source.provider }
    private var metrics: [MobileUsageMetric] { store.customizableMetrics(for: provider) }
    private var settings: MobileMetricDisplaySettings { store.metricSettings(for: provider.providerID) }
    private var visibleCount: Int { store.providerDisplaySettings.visibleMetrics(for: provider).count }

    var body: some View {
        List {
            Section {
                Toggle(
                    "Show This Provider",
                    isOn: Binding(
                        get: { !store.providerDisplaySettings.hiddenProviderIDs.contains(provider.providerID) },
                        set: { store.setProvider(provider.providerID, isVisible: $0) }
                    )
                )
            } footer: {
                Text("Applies to the Today screen and both widgets.")
            }

            Section {
                Picker(
                    "Card Detail",
                    selection: Binding(
                        get: { settings.detail },
                        set: { store.setDetail($0, forProvider: provider.providerID) }
                    )
                ) {
                    ForEach(MobileMetricDisplaySettings.Detail.allCases) { detail in
                        Text(detail.title).tag(detail)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Card Detail")
            } footer: {
                Text(settings.detail.summary)
            }

            if metrics.isEmpty {
                Section {
                    Label("This Mac published no numeric metrics for \(provider.displayName)", systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(metrics) { metric in
                        metricRow(metric)
                    }
                    .onMove { offsets, destination in
                        store.moveMetrics(for: provider, fromOffsets: offsets, toOffset: destination)
                    }
                } header: {
                    Text("Metrics")
                } footer: {
                    Text("The first visible metric is the headline on the card and in the widgets. Tap Edit to reorder.")
                }
            }

            if settings.isCustomized {
                Section {
                    Button("Reset \(provider.displayName)") {
                        store.resetMetricSettings(forProvider: provider.providerID)
                    }
                } footer: {
                    Text("Shows every metric again in the order your Mac publishes them.")
                }
            }
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    private func metricRow(_ metric: MobileUsageMetric) -> some View {
        let isVisible = store.isMetricVisible(metric.id, forProvider: provider.providerID)
        return Toggle(
            isOn: Binding(
                get: { isVisible },
                set: { store.setMetric(metric.id, isVisible: $0, forProvider: provider.providerID) }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.label)
                Text(MobileFormatting.remaining(metric, hidesFinancialValues: store.hidesFinancialValues))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        // A provider always keeps one visible metric, so its card and widgets never go blank.
        .disabled(isVisible && visibleCount == 1)
    }
}
