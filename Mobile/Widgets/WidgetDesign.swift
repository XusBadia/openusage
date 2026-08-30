import OpenUsageMobileCore
import SwiftUI
import UIKit

enum WidgetDesign {
    static func accent(for providerID: String) -> Color {
        let family = providerID.split(separator: "@").first.map(String.init) ?? providerID
        switch family {
        case "claude": return Color(red: 0.85, green: 0.47, blue: 0.34)
        case "codex": return Color(red: 0.55, green: 0.49, blue: 0.96)
        case "cursor": return Color(red: 0.31, green: 0.62, blue: 0.56)
        default: return .accentColor
        }
    }

    static func quotaColor(_ metric: MobileUsageMetric, providerID: String) -> Color {
        guard let fraction = metric.remainingFraction else { return accent(for: providerID) }
        if fraction <= 0.1 { return .red }
        if fraction <= 0.2 { return .orange }
        return accent(for: providerID)
    }
}

struct WidgetProviderIcon: View {
    let providerID: String
    var size: CGFloat = 24

    private var family: String {
        providerID.split(separator: "@").first.map(String.init) ?? providerID
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(WidgetDesign.accent(for: providerID).opacity(0.14))
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(WidgetDesign.accent(for: providerID))
                    .padding(size * 0.22)
            } else {
                Text(String(family.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetDesign.accent(for: providerID))
            }
        }
        .frame(width: size, height: size)
    }

    private var image: UIImage? {
        UIImage(named: family)?.withRenderingMode(.alwaysTemplate)
    }
}

enum WidgetFormatting {
    static func remaining(_ metric: MobileUsageMetric, hidesFinancialValues: Bool) -> String {
        guard let used = metric.used, let limit = metric.limit, let unit = metric.unit else {
            return value(metric.values.first, hidesFinancialValues: hidesFinancialValues)
        }
        let remaining = max(0, limit - used)
        switch unit.kind {
        case .percent: return "\(Int(remaining.rounded()))%"
        case .dollars: return hidesFinancialValues ? "••••" : remaining.formatted(.currency(code: "USD"))
        case .count: return remaining.formatted(.number.notation(.compactName))
        }
    }

    static func value(_ value: MobileMetricValue?, hidesFinancialValues: Bool) -> String {
        guard let value else { return "—" }
        switch value.unit.kind {
        case .percent: return "\(Int(value.number.rounded()))%"
        case .dollars: return hidesFinancialValues ? "••••" : value.number.formatted(.currency(code: "USD"))
        case .count: return value.number.formatted(.number.notation(.compactName))
        }
    }

    static func reset(_ date: Date, now: Date) -> String {
        guard date > now else { return "Reset due" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Resets \(formatter.localizedString(for: date, relativeTo: now))"
    }
}

struct WidgetQuotaBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(5, proxy.size.width * max(0, min(1, fraction))))
            }
        }
        .frame(height: 6)
    }
}
