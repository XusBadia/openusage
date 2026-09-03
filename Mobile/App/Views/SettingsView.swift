import OpenUsageMobileCore
import SwiftUI
import UserNotifications
import UIKit

struct SettingsView: View {
    @Environment(MobileDashboardStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationAuthorization: UNAuthorizationStatus = .notDetermined

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

                Text("Choose which providers and metrics appear, and how much of each one a card shows. Your choices are shared with widgets.")
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

            Section("Notifications") {
                Toggle(
                    "Usage Alerts",
                    isOn: Binding(
                        get: { store.notificationSettings.isEnabled },
                        set: { setNotificationsEnabled($0) }
                    )
                )

                if store.notificationSettings.isEnabled {
                    NavigationLink {
                        NotificationProviderSettingsView()
                    } label: {
                        LabeledContent {
                            Text(providerAlertSummary)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Provider Alerts", systemImage: "bell.badge")
                        }
                    }

                    Toggle(
                        "Sounds",
                        isOn: Binding(
                            get: { store.notificationSettings.soundEnabled },
                            set: { store.setNotificationSoundEnabled($0) }
                        )
                    )

                    if !notificationsAreAuthorized {
                        Label(
                            notificationAuthorization == .denied
                                ? "Notifications are off in iOS Settings"
                                : "Notification permission is required",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)

                        Button(notificationPermissionButtonTitle) {
                            Task { await requestNotificationAuthorization() }
                        }
                    }
                }

                Text(
                    "Alerts are checked when OpenUsage or one of its widgets refreshes iCloud. "
                        + "Each visible quota alerts at the milestones you choose, when exhausted, and when it resets."
                )
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
        .task { await refreshNotificationAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshNotificationAuthorization() }
        }
    }

    private var providerAlertSummary: String {
        let enabled = store.customizableProviders.filter {
            store.notificationSettings(for: $0.provider.providerID).isEnabled
        }.count
        return "\(enabled) of \(store.customizableProviders.count)"
    }

    private var notificationsAreAuthorized: Bool {
        switch notificationAuthorization {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    private var notificationPermissionButtonTitle: String {
        notificationAuthorization == .denied ? "Open Notification Settings" : "Allow Notifications"
    }

    private func setNotificationsEnabled(_ enabled: Bool) {
        store.setNotificationsEnabled(enabled)
        guard enabled else { return }
        Task { await requestNotificationAuthorization() }
    }

    private func requestNotificationAuthorization() async {
        if notificationAuthorization == .denied {
            await UIApplication.shared.open(URL(string: UIApplication.openNotificationSettingsURLString)!)
            return
        }
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            // The status row stays visible; returning to Settings retries the live system status.
        }
        await refreshNotificationAuthorization()
    }

    private func refreshNotificationAuthorization() async {
        notificationAuthorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if notificationsAreAuthorized {
            await store.reconcileNotificationSchedule()
        }
    }
}

private struct NotificationProviderSettingsView: View {
    @Environment(MobileDashboardStore.self) private var store

    var body: some View {
        List {
            ForEach(store.customizableProviders) { source in
                let provider = source.provider
                let settings = store.notificationSettings(for: provider.providerID)
                Section {
                    Toggle(
                        "Usage Alerts",
                        isOn: Binding(
                            get: { store.notificationSettings(for: provider.providerID).isEnabled },
                            set: { store.setProviderNotifications(provider.providerID, isEnabled: $0) }
                        )
                    )
                    ForEach(MobileUsageAlertThreshold.allCases) { threshold in
                        Toggle(
                            threshold.title,
                            isOn: Binding(
                                get: {
                                    store.notificationSettings(for: provider.providerID)
                                        .thresholds.contains(threshold)
                                },
                                set: {
                                    store.setNotificationThreshold(
                                        threshold,
                                        isEnabled: $0,
                                        for: provider.providerID
                                    )
                                }
                            )
                        )
                        .disabled(!settings.isEnabled)
                    }

                    Toggle(
                        "Quota Reset",
                        isOn: Binding(
                            get: { store.notificationSettings(for: provider.providerID).resetEnabled },
                            set: {
                                store.setProviderResetNotifications(provider.providerID, isEnabled: $0)
                            }
                        )
                    )
                    .disabled(!settings.isEnabled)
                } header: {
                    Label {
                        Text(provider.displayName)
                    } icon: {
                        ProviderIconView(providerID: provider.providerID, size: 22)
                    }
                } footer: {
                    Text("The 100% limit alert is always included. Reset alerts arrive at the provider's published reset time.")
                }
            }
        }
        .navigationTitle("Provider Alerts")
        .navigationBarTitleDisplayMode(.inline)
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
