import SwiftUI

struct ICloudSyncSettingsSection: View {
    @Bindable var sync: ICloudUsageSyncStore
    @AppStorage(DensitySetting.key) private var density = DensitySetting.regular

    var body: some View {
        VStack(alignment: .leading, spacing: density.headerToCardSpacing) {
            HStack(spacing: 5) {
                Text("iCloud Sync")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "info.circle")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .hoverTooltip(
                        "OpenUsage calculates costs and tokens for Claude, Codex, and other providers "
                            + "from files stored on each Mac. Credentials, prompts, logs, account "
                            + "identities, and raw provider responses are never shared."
                    )
            }
            .padding(.horizontal, 8)

            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    Text("Sync Across Macs")
                    if sync.enabled, sync.isSyncing, sync.serviceError == nil {
                        MotionAwareProgressView(controlSize: .small)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                            .accessibilityLabel("Syncing usage history")
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $sync.enabled)
                        .settingsSwitchStyle()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, density.controlRowPadding)
                .animation(Motion.spring, value: sync.isSyncing)
                Text("Shares usage history through iCloud, so you can see one combined summary for all your Macs.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)

                if sync.enabled { enabledContent }

                Divider()

                HStack(spacing: 7) {
                    Text("Share Usage With Mobile Devices")
                    if sync.mobileStatusEnabled, sync.isSyncing, sync.mobileStatusError == nil {
                        MotionAwareProgressView(controlSize: .small)
                            .accessibilityLabel("Sharing mobile usage status")
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $sync.mobileStatusEnabled)
                        .settingsSwitchStyle()
                }
                .padding(.horizontal, 12)
                .padding(.top, density.controlRowPadding)

                Text("Shares sanitized quotas, reset times, balances, and plan names. This is separate from usage history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, sync.mobileStatusEnabled ? 4 : 10)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if sync.mobileStatusEnabled { mobileStatusContent }
            }
            .cardSurface()
        }
    }

    @ViewBuilder
    private var mobileStatusContent: some View {
        if let error = sync.mobileStatusError {
            inlineNotice(error)
        } else if let updatedAt = sync.mobileStatusUpdatedAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Label("Shared \(Formatters.relativeAge(since: updatedAt, now: context.date))", systemImage: "iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if !sync.isSyncing {
            Text("Waiting for the first mobile update…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var enabledContent: some View {
        Divider()
        if let error = sync.serviceError { inlineNotice(error) }

        if sync.displayedDocuments.isEmpty, !sync.isSyncing, sync.serviceError == nil {
            Text("Waiting for this Mac’s first iCloud update…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(sync.displayedDocuments) { document in
                deviceRow(document, isThisMac: document.deviceID == sync.deviceID)
            }
        }
    }

    private func deviceRow(_ document: UsageHistoryDocument, isThisMac: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isThisMac ? "laptopcomputer" : "desktopcomputer")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(document.deviceName)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isThisMac {
                        Text("This Mac")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.12), in: Capsule())
                            .fixedSize()
                    }
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text("Updated \(Formatters.relativeAge(since: document.updatedAt, now: context.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, density.controlRowPadding)
    }

    private func inlineNotice(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.notice)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

}
