import Foundation
import OpenUsageMobileCore
import SwiftUI
import UIKit

enum MobilePalette {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let raisedSurface = Color(uiColor: .tertiarySystemGroupedBackground)
    static let hairline = Color(uiColor: .separator).opacity(0.38)
    static let track = Color.secondary.opacity(0.14)

    static func accent(for providerID: String) -> Color {
        let family = providerID.split(separator: "@").first.map(String.init) ?? providerID
        switch family {
        case "claude": return Color(hex: "#D97757")
        case "codex": return Color(hex: "#8C7CF6")
        case "cursor": return Color(hex: "#4E9E8F")
        case "grok": return Color(hex: "#6C778A")
        case "copilot": return Color(hex: "#5C7CFA")
        case "opencode": return Color(hex: "#45A679")
        default: return Color.accentColor
        }
    }

    static func quotaColor(for metric: MobileUsageMetric, providerID: String) -> Color {
        guard let remaining = metric.remainingFraction else {
            return metric.colorHex.map(Color.init(hex:)) ?? accent(for: providerID)
        }
        if remaining <= 0.1 { return .red }
        if remaining <= 0.2 { return .orange }
        return metric.colorHex.map(Color.init(hex:)) ?? accent(for: providerID)
    }
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let number = UInt64(value, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct ProviderIconView: View {
    let providerID: String
    var size: CGFloat = 36

    private var family: String {
        providerID.split(separator: "@").first.map(String.init) ?? providerID
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(MobilePalette.accent(for: providerID).opacity(0.14))
            if let image = providerImage {
                Image(uiImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(MobilePalette.accent(for: providerID))
                    .padding(size * 0.22)
            } else {
                Text(String(family.prefix(1)).uppercased())
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(MobilePalette.accent(for: providerID))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var providerImage: UIImage? {
        UIImage(named: family)?.withRenderingMode(.alwaysTemplate)
    }
}

struct QuotaProgressView: View {
    let fraction: Double
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MobilePalette.track)
                Capsule()
                    .fill(color)
                    .frame(width: max(8, proxy.size.width * max(0, min(1, fraction))))
            }
        }
        .frame(height: 8)
        .animation(
            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 1),
            value: fraction
        )
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent available")
    }
}

struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(MobilePalette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(MobilePalette.hairline, lineWidth: 0.5)
            }
    }
}

extension View {
    func cardSurface() -> some View { modifier(CardSurface()) }
}

enum MobileFormatting {
    static func remaining(_ metric: MobileUsageMetric, hidesFinancialValues: Bool = false) -> String {
        guard let used = metric.used, let limit = metric.limit, let unit = metric.unit else {
            return value(metric.values.first, hidesFinancialValues: hidesFinancialValues)
        }
        let remaining = max(0, limit - used)
        switch unit.kind {
        case .percent: return "\(Int(remaining.rounded()))% available"
        case .dollars: return hidesFinancialValues ? "••••" : "\(currency(remaining)) available"
        case .count: return "\(compact(remaining)) \(unit.suffix ?? "available")"
        }
    }

    static func value(_ value: MobileMetricValue?, hidesFinancialValues: Bool = false) -> String {
        guard let value else { return "No data" }
        switch value.unit.kind {
        case .percent: return "\(Int(value.number.rounded()))%"
        case .dollars: return hidesFinancialValues ? "••••" : currency(value.number)
        case .count:
            return [compact(value.number), value.label ?? value.unit.suffix].compactMap { $0 }.joined(separator: " ")
        }
    }

    static func compact(_ number: Double) -> String {
        number.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func currency(_ number: Double) -> String {
        number.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    static func reset(_ date: Date, now: Date = Date()) -> String {
        if date <= now { return "Reset due" }
        guard let duration = detailedDuration(date.timeIntervalSince(now), rounding: .up) else {
            return "Reset due"
        }
        return "Resets in \(duration)"
    }

    static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        guard seconds >= 60,
              let duration = detailedDuration(seconds, rounding: .down) else { return "just now" }
        return "\(duration) ago"
    }

    /// Two-unit relative duration for app surfaces with room for useful precision. Home Screen widgets
    /// deliberately keep their separate one-unit formatter because their labels are width-constrained.
    private static func detailedDuration(
        _ seconds: TimeInterval,
        rounding rule: FloatingPointRoundingRule
    ) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let totalMinutes = max(1, Int((seconds / 60).rounded(rule)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }

    static func date(fromDayKey value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
