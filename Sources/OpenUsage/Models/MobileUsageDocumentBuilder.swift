import Foundation
import OpenUsageMobileCore

extension ProviderSnapshot {
    /// - Parameter metricTitles: Registered widget-descriptor titles keyed by the lowercased metric
    ///   label their provider emits. Only a line whose label a descriptor declares is named on mobile,
    ///   so dynamic text (custom model names, org names) can never ride along in a label.
    func mobileSnapshot(status: MobileProviderStatus, metricTitles: [String: String]) -> MobileProviderSnapshot {
        var mobileMetrics: [MobileUsageMetric] = []
        var usedIDs: Set<String> = []
        for (index, line) in lines.enumerated() {
            guard var metric = line.mobileMetric(providerID: providerID, index: index, metricTitles: metricTitles)
            else { continue }
            metric.id = Self.uniqueMetricID(metric.id, fallback: "\(providerID).metric-\(index)", used: &usedIDs)
            mobileMetrics.append(metric)
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

    /// Metric ids are derived from the metric's name so a phone's saved metric order and hidden metrics
    /// survive a Mac publishing one more (or one fewer) line. Two lines that resolve to the same name
    /// keep their position via a numeric suffix.
    private static func uniqueMetricID(_ candidate: String, fallback: String, used: inout Set<String>) -> String {
        var id = candidate.isEmpty ? fallback : candidate
        var attempt = 2
        while used.contains(id) {
            id = "\(candidate.isEmpty ? fallback : candidate)-\(attempt)"
            attempt += 1
        }
        used.insert(id)
        return id
    }
}

private extension MetricLine {
    func mobileMetric(providerID: String, index: Int, metricTitles: [String: String]) -> MobileUsageMetric? {
        switch self {
        case .progress(let label, let used, let limit, let format, let resetsAt, let periodDurationMs, let colorHex):
            guard used.isFinite, limit.isFinite, limit > 0 else { return nil }
            let safeUsed = format == .percent
                ? min(100, max(0, used))
                : max(0, used)
            let name = label.mobileMetricLabel(titles: metricTitles, fallback: "Quota \(index + 1)")
            return MobileUsageMetric(
                id: name.mobileMetricID(providerID: providerID),
                label: name,
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
            let name = label.mobileMetricLabel(titles: metricTitles, fallback: "Usage \(index + 1)")
            return MobileUsageMetric(
                id: name.mobileMetricID(providerID: providerID),
                label: name,
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
    /// The Mac dashboard's own title for this metric, matched by the label the provider emits. An
    /// unmatched label is dynamic text (a custom model name, an organization) and is replaced by a
    /// neutral placeholder rather than published.
    func mobileMetricLabel(titles: [String: String], fallback: String) -> String {
        let key = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return titles[key]?.mobileSafeText(maximumLength: 80) ?? fallback
    }

    /// A stable, name-derived metric id: "claude.session", "codex.spark-weekly".
    func mobileMetricID(providerID: String) -> String {
        let slug = lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "" : "\(providerID).\(slug)"
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
        // Provider ids are code-authored slugs, so a provider that ships before this list is updated
        // still reads as itself instead of a generic "Provider".
        default: family.isEmpty ? "Provider" : family.prefix(1).uppercased() + family.dropFirst()
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
                providers[providerID] = snapshot.mobileSnapshot(
                    status: status,
                    metricTitles: mobileMetricTitles(providerID: providerID)
                )
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

    /// A provider's registered metric titles keyed by the label its lines carry. This is the allowlist
    /// the mobile document names metrics from: every entry is copy declared in a widget descriptor, and
    /// the phone ends up showing the same name as the Mac dashboard.
    private func mobileMetricTitles(providerID: String) -> [String: String] {
        registry.descriptors(for: providerID).reduce(into: [String: String]()) { titles, descriptor in
            let key = descriptor.metricLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, titles[key] == nil else { return }
            titles[key] = descriptor.title
        }
    }
}
