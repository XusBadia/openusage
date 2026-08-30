import Foundation
import OpenUsageMobileCore

extension ProviderSnapshot {
    func mobileSnapshot(status: MobileProviderStatus) -> MobileProviderSnapshot {
        let mobileMetrics = lines.enumerated().compactMap { index, line in
            line.mobileMetric(providerID: providerID, index: index)
        }
        return MobileProviderSnapshot(
            providerID: providerID,
            displayName: providerID.mobileProviderDisplayName,
            plan: plan?.mobileSafeText(maximumLength: 80),
            refreshedAt: refreshedAt,
            status: status,
            metrics: mobileMetrics
        )
    }
}

private extension MetricLine {
    func mobileMetric(providerID: String, index: Int) -> MobileUsageMetric? {
        let id = "\(providerID).metric-\(index)"
        switch self {
        case .progress(let label, let used, let limit, let format, let resetsAt, let periodDurationMs, let colorHex):
            guard used.isFinite, limit.isFinite, limit > 0 else { return nil }
            let safeUsed = format == .percent
                ? min(100, max(0, used))
                : max(0, used)
            return MobileUsageMetric(
                id: id,
                label: label.mobileMetricLabel(fallback: "Quota \(index + 1)"),
                presentation: .progress,
                used: safeUsed,
                limit: limit,
                unit: format.mobileUnit,
                resetsAt: resetsAt,
                periodDurationMilliseconds: periodDurationMs,
                colorHex: colorHex?.mobileColorHex
            )
        case .values(let label, let values, let colorHex, let expiriesAt, _, _):
            let safeValues = values.compactMap(\.mobileValue)
            guard !safeValues.isEmpty else { return nil }
            return MobileUsageMetric(
                id: id,
                label: label.mobileMetricLabel(fallback: "Usage \(index + 1)"),
                presentation: .values,
                values: safeValues,
                expiriesAt: expiriesAt,
                colorHex: colorHex?.mobileColorHex
            )
        case .text, .badge, .chart:
            // Raw notices, error strings, charts, model names, and source notes stay on the Mac.
            return nil
        }
    }
}

private extension ProgressFormat {
    var mobileUnit: MobileMetricUnit {
        switch self {
        case .percent: MobileMetricUnit(kind: .percent)
        case .dollars: MobileMetricUnit(kind: .dollars)
        case .count(let suffix): MobileMetricUnit(kind: .count, suffix: suffix.mobileCountSuffix)
        }
    }
}

private extension MetricValue {
    var mobileValue: MobileMetricValue? {
        guard number.isFinite, number >= 0 else { return nil }
        return MobileMetricValue(
            number: number,
            unit: kind.mobileUnit,
            label: label?.mobileValueLabel,
            estimated: estimated
        )
    }
}

private extension MetricKind {
    var mobileUnit: MobileMetricUnit {
        switch self {
        case .percent: MobileMetricUnit(kind: .percent)
        case .dollars: MobileMetricUnit(kind: .dollars)
        case .count: MobileMetricUnit(kind: .count)
        }
    }
}

private extension String {
    func mobileMetricLabel(fallback: String) -> String {
        switch lowercased() {
        case "session": "Session"
        case "weekly": "Weekly"
        case "daily": "Daily"
        case "monthly": "Monthly"
        case "5-hour limit": "5-hour limit"
        case "weekly limit": "Weekly limit"
        case "total usage": "Total usage"
        case "requests": "Requests"
        case "cursor models": "Cursor Models"
        case "other models": "Other Models"
        case "on-demand": "On-demand"
        case "extra usage spent": "Extra usage spent"
        case "extra usage balance": "Extra usage balance"
        case "credits": "Credits"
        case "balance": "Balance"
        case "today": "Today"
        case "yesterday": "Yesterday"
        case "this week": "This Week"
        case "this month": "This Month"
        case "last 7 days": "Last 7 Days"
        case "last 30 days": "Last 30 Days"
        case "key limit": "Key Limit"
        case "rate limit resets": "Rate Limit Resets"
        case "chat": "Chat"
        case "completions": "Completions"
        case "org credits": "Org Credits"
        case "org spend": "Org Spend"
        case "extra usage": "Extra Usage"
        case "web searches": "Web Searches"
        default: fallback
        }
    }

    var mobileValueLabel: String? {
        switch lowercased() {
        case "available": "available"
        case "credits": "credits"
        case "tokens": "tokens"
        default: nil
        }
    }

    var mobileCountSuffix: String? {
        switch lowercased() {
        case "credits": "credits"
        case "requests": "requests"
        case "resets": "resets"
        case "searches": "searches"
        case "tokens": "tokens"
        default: nil
        }
    }

    var mobileProviderDisplayName: String {
        let family = split(separator: "@", maxSplits: 1).first.map(String.init)?.lowercased() ?? lowercased()
        return switch family {
        case "antigravity": "Antigravity"
        case "claude": "Claude"
        case "codex": "Codex"
        case "copilot": "Copilot"
        case "cursor": "Cursor"
        case "devin": "Devin"
        case "grok": "Grok"
        case "opencode": "OpenCode"
        case "openrouter": "OpenRouter"
        case "zai": "Z.ai"
        default: "Provider"
        }
    }

    func mobileSafeText(maximumLength: Int) -> String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= maximumLength,
              value.rangeOfCharacter(from: .controlCharacters) == nil
        else { return nil }
        return value
    }

    var mobileColorHex: String? {
        range(of: #"^#[A-Fa-f0-9]{6}$"#, options: .regularExpression) == nil ? nil : self
    }
}

extension WidgetDataStore {
    func localMobileUsageDocument(
        deviceID: String,
        deviceName: String,
        updatedAt: Date = Date()
    ) -> MobileUsageDocument {
        let descriptorOrder = orderedDescriptors().map(\.providerID)
        let registryOrder = registry.providers.map(\.id)
        var seen = Set<String>()
        let orderedProviderIDs = (descriptorOrder + registryOrder).filter { seen.insert($0).inserted }

        var providers: [String: MobileProviderSnapshot] = [:]
        for providerID in orderedProviderIDs where isProviderEnabled(providerID) {
            if let snapshot = localSnapshots[providerID] {
                let status: MobileProviderStatus = if providerErrors[providerID] != nil {
                    .unavailable
                } else if snapshot.warning != nil {
                    .attention
                } else {
                    .available
                }
                providers[providerID] = snapshot.mobileSnapshot(status: status)
            } else if providerErrors[providerID] != nil,
                      registry.provider(id: providerID) != nil
            {
                providers[providerID] = MobileProviderSnapshot(
                    providerID: providerID,
                    displayName: providerID.mobileProviderDisplayName,
                    refreshedAt: updatedAt,
                    status: .unavailable,
                    metrics: []
                )
            }
        }

        return MobileUsageDocument(
            deviceID: deviceID,
            deviceName: deviceName,
            updatedAt: updatedAt,
            providerOrder: orderedProviderIDs.filter { providers[$0] != nil },
            providers: providers
        )
    }
}
