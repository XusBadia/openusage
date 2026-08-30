import SwiftUI

struct OnboardingView: View {
    var errorMessage: String?
    @Environment(MobileDashboardStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                VStack(spacing: 0) {
                    step(number: 1, title: "Use the Same Apple Account", detail: "Sign in to iCloud Drive on this iPhone and your Mac.")
                    Divider().padding(.leading, 52)
                    step(number: 2, title: "Enable Mobile Sharing on Your Mac", detail: "In OpenUsage Settings, turn on Share Usage With Mobile Devices.")
                    Divider().padding(.leading, 52)
                    step(number: 3, title: "Keep the Mac App Running", detail: "The Mac checks providers and publishes a sanitized snapshot about every five minutes.")
                }
                .cardSurface()

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                }

                Button {
                    Task { await store.refresh() }
                } label: {
                    HStack {
                        if store.isRefreshing { ProgressView().controlSize(.small) }
                        Text(store.isRefreshing ? "Checking iCloud…" : "Check Again")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isRefreshing)

                Text("Credentials, prompts, logs, account identities, and raw provider responses stay on your Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(MobilePalette.canvas.ignoresSafeArea())
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            Text("Your Usage, Away From the Mac")
                .font(.largeTitle.bold())
                .tracking(-0.6)
            Text("See what’s available and when limits reset. Your Mac remains the source of truth.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 28)
    }

    private func step(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }
}
