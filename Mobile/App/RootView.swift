import SwiftUI

struct RootView: View {
    @Environment(MobileDashboardStore.self) private var store
    @State private var selectedTab = AppConfiguration.previewTab

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                ProgressView("Checking iCloud…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MobilePalette.canvas)
            case .waitingForMac:
                OnboardingView()
            case .failure(let message):
                OnboardingView(errorMessage: message)
            case .content:
                dashboard
            }
        }
        .tint(.accentColor)
    }

    private var dashboard: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label("Today", systemImage: "gauge.with.dots.needle.67percent") }
            .tag(0)

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("History", systemImage: "chart.bar.xaxis") }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(2)
        }
        .overlay(alignment: .top) {
            if let notice = store.refreshNotice {
                RefreshNoticeBanner(message: notice)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
    }
}

private struct RefreshNoticeBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "icloud.slash")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityAddTraits(.isStaticText)
    }
}
