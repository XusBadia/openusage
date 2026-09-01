import AppKit
import Foundation
import OpenUsageMobileBridgeCore
import OSLog
import ServiceManagement

@main
enum OpenUsageMobileBridgeMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = BridgeAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
private final class BridgeAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: BridgeController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier {
            let peers = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !peers.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }
        controller = BridgeController()
        controller?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}

@MainActor
private final class BridgeController: NSObject {
    private static let deviceIDKey = "openusage.mobileBridge.deviceID.v1"
    private static let legacyDeviceIDKey = "openusage.icloudSync.deviceID.v1"
    private static let syncInterval: Duration = .seconds(300)

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.badia.ailimits.collector",
        category: "bridge"
    )
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let client = OpenUsageLocalClient()
    private let deviceID: String
    private let deviceName: String
    private var loopTask: Task<Void, Never>?
    private var isSyncing = false
    private var lastSync: Date?
    private var statusMessage = "Waiting for the first sync…"
    private var statusIsError = false

    override init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: Self.deviceIDKey), !saved.isEmpty {
            deviceID = saved
        } else if let legacy = defaults.string(forKey: Self.legacyDeviceIDKey), !legacy.isEmpty {
            deviceID = legacy
            defaults.set(legacy, forKey: Self.deviceIDKey)
        } else {
            let created = UUID().uuidString.lowercased()
            defaults.set(created, forKey: Self.deviceIDKey)
            deviceID = created
        }
        let hostName = Host.current().localizedName ?? Host.current().name ?? "Mac"
        let trimmed = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
        deviceName = String((trimmed.isEmpty ? "Mac" : trimmed).prefix(120))
        super.init()
    }

    func start() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "iphone.and.arrow.forward",
            accessibilityDescription: "OpenUsage Mobile Bridge"
        )
        statusItem.button?.image?.isTemplate = true
        registerForLoginIfNeeded()
        rebuildMenu()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncNow()
                do { try await Task.sleep(for: Self.syncInterval) }
                catch { return }
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        statusMessage = "Syncing with OpenUsage…"
        statusIsError = false
        rebuildMenu()
        defer { isSyncing = false }

        do {
            let payload = try await client.load()
            let now = Date()
            let document = try OpenUsageBridgeMapper.makeDocument(
                payload: payload,
                deviceID: deviceID,
                deviceName: deviceName,
                updatedAt: now
            )
            guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
                throw MobileBridgePublisherError.iCloudUnavailable
            }
            let publisher = MobileBridgePublisher(containerURL: containerURL)
            try await publisher.publish(document)
            let historyCount = try await publisher.mirrorHistory(from: officialHistoryDirectory())

            lastSync = now
            statusMessage = historyCount == 0
                ? "Usage synced. History sync is off in OpenUsage."
                : "Usage and history synced."
            statusIsError = false
            logger.info("Published \(document.providers.count, privacy: .public) providers and \(historyCount, privacy: .public) history documents")
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
            logger.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
        rebuildMenu()
    }

    private func officialHistoryDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Mobile Documents", isDirectory: true)
            .appendingPathComponent("iCloud~com~robinebers~openusage", isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("OpenUsage", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    private func registerForLoginIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let service = SMAppService.mainApp
        guard service.status == .notRegistered else { return }
        do {
            try service.register()
        } catch {
            statusMessage = "Usage sync works now, but Launch at Login needs attention: \(error.localizedDescription)"
            statusIsError = true
            logger.error("Could not register Launch at Login: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "OpenUsage Mobile Bridge", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let statusPrefix = statusIsError ? "Problem: " : ""
        let status = NSMenuItem(title: statusPrefix + statusMessage, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if let lastSync {
            let date = DateFormatter.localizedString(from: lastSync, dateStyle: .none, timeStyle: .medium)
            let last = NSMenuItem(title: "Last Sync: \(date)", action: nil, keyEquivalent: "")
            last.isEnabled = false
            menu.addItem(last)
        }

        menu.addItem(.separator())
        let sync = NSMenuItem(title: "Sync Now", action: #selector(syncNowAction), keyEquivalent: "r")
        sync.target = self
        sync.isEnabled = !isSyncing
        menu.addItem(sync)

        let openUsage = NSMenuItem(title: "Open OpenUsage", action: #selector(openOpenUsage), keyEquivalent: "")
        openUsage.target = self
        menu.addItem(openUsage)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Bridge", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func syncNowAction() {
        Task { await syncNow() }
    }

    @objc private func openOpenUsage() {
        let url = URL(fileURLWithPath: "/Applications/OpenUsage.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error {
                self.logger.error("Could not open OpenUsage: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
            statusIsError = false
        } catch {
            statusMessage = "Couldn’t change Launch at Login: \(error.localizedDescription)"
            statusIsError = true
        }
        rebuildMenu()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
