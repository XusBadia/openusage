import Foundation

enum AppConfiguration {
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Usage Companion"
    }

    static var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
            ?? "group.com.example.usage-companion"
    }

    static var usesPreviewData: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-preview")
    }

    static var previewTab: Int {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-preview-tab"),
              arguments.indices.contains(flagIndex + 1)
        else { return 0 }
        switch arguments[flagIndex + 1] {
        case "history": return 1
        case "settings": return 2
        default: return 0
        }
    }
}
