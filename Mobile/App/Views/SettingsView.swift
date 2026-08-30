import OpenUsageMobileCore
import SwiftUI

struct SettingsView: View {
    @Environment(MobileDashboardStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List {
            Section("Display") {
                NavigationLink {
                    ProviderCustomizationView()
                } label: {
                    LabeledContent {
                        Text("\(store.providers.count) of \(store.customizableProviders.count)")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Providers", systemImage: "square.3.layers.3d")
                    }
                }

                Text("Your provider selection and order are shared with widgets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Synchronization") {
                Button {
                    Task { await store.refresh() }
                } label: {
                    HStack {
                        Label("Check iCloud", systemImage: "arrow.clockwise.icloud")
                        Spacer()
                        if store.isRefreshing { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(store.isRefreshing)

                if store.devices.isEmpty {
                    Label("No Macs have published data yet", systemImage: "laptopcomputer.slash")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.devices) { device in
                        DeviceSettingsRow(device: device)
                    }
                }

                Text("Checking iCloud does not contact providers or wake a Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Toggle(
                    "Hide Costs and Balances",
                    isOn: Binding(
                        get: { store.hidesFinancialValues },
                        set: { store.setHidesFinancialValues($0) }
                    )
                )
                Label("Credentials and raw activity stay on your Mac", systemImage: "lock.shield")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Widgets may show quota and reset information on the Home Screen. Account identities are never included.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.invalidFileCount > 0 {
                Section("Sync Health") {
                    Label(
                        "\(store.invalidFileCount) invalid synced file\(store.invalidFileCount == 1 ? "" : "s") ignored",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section("About This Beta") {
                LabeledContent("App", value: AppConfiguration.displayName)
                LabeledContent("Data Source", value: "Your Mac via iCloud")
                LabeledContent("Provider Refresh", value: "About every 5 minutes")
                Text("This development build uses configurable signing and branding so an authorized maintainer can produce an official distribution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
    }
}

struct ProviderCustomizationView: View {
    @Environment(MobileDashboardStore.self) private var store
    @State private var editMode: EditMode = .active

    var body: some View {
        List {
            Section {
                ForEach(store.customizableProviders) { source in
                    providerRow(source)
                }
                .onMove(perform: store.moveProviders)
            } header: {
                Text("Provider Order")
            } footer: {
                Text("Drag to reorder. Hidden providers stay synced and can be shown again at any time.")
            }

            if store.providerListIsCustomized {
                Section {
                    Button("Reset Provider List", action: store.resetProviderDisplaySettings)
                } footer: {
                    Text("Shows every provider and restores the order published by your Mac.")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Providers")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func providerRow(_ source: ResolvedMobileProvider) -> some View {
        let provider = source.provider
        return HStack(spacing: 12) {
            ProviderIconView(providerID: provider.providerID, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.body.weight(.medium))
                if let plan = provider.plan {
                    Text(plan)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(
                "Show \(provider.displayName)",
                isOn: Binding(
                    get: { !store.providerDisplaySettings.hiddenProviderIDs.contains(provider.providerID) },
                    set: { store.setProvider(provider.providerID, isVisible: $0) }
                )
            )
            .labelsHidden()
        }
        .accessibilityElement(children: .contain)
    }
}

private struct DeviceSettingsRow: View {
    let device: MobileDeviceSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "laptopcomputer")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.name).font(.body.weight(.medium))
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text("Updated \(MobileFormatting.age(device.updatedAt, now: context.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 5) {
                if device.publishesStatus {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .accessibilityLabel("Publishes quotas")
                }
                if device.publishesHistory {
                    Image(systemName: "chart.bar.xaxis")
                        .accessibilityLabel("Publishes history")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
