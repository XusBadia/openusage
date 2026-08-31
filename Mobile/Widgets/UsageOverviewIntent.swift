import AppIntents
import OpenUsageMobileCore

/// Which providers this particular overview widget lists, in what order, how many, and how much of each.
///
/// Every parameter has a default that reproduces what the widget did before it was configurable, so an
/// overview already on someone's Home Screen keeps looking the same until they choose otherwise.
struct UsageOverviewIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Usage Overview"
    static let description = IntentDescription(
        "Choose which providers this widget lists, how they are ordered, and how much of each one it shows."
    )

    /// Leave empty to follow the providers chosen in the app. Picking providers here overrides that for
    /// this widget only, so two overviews can watch different things.
    @Parameter(title: "Providers")
    var providers: [ProviderWidgetEntity]?

    @Parameter(title: "Order", default: .yourOrder)
    var sort: OverviewSortOption

    @Parameter(title: "Rows", default: .automatic)
    var rows: OverviewRowCount

    @Parameter(title: "Row Detail", default: .standard)
    var detail: OverviewRowDetail

    @Parameter(title: "Show Title", default: true)
    var showsHeader: Bool

    @Parameter(title: "Show Reset Times", default: true)
    var showsResets: Bool

    @Parameter(title: "Show Plan Names", default: false)
    var showsPlans: Bool
}

enum OverviewSortOption: String, AppEnum, CaseIterable {
    case yourOrder
    case leastLeft
    case soonestReset

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Order")
    static let caseDisplayRepresentations: [OverviewSortOption: DisplayRepresentation] = [
        .yourOrder: DisplayRepresentation(title: "Your Order", subtitle: "The order you set in the app"),
        .leastLeft: DisplayRepresentation(title: "Least Left First", subtitle: "Whatever is closest to running out"),
        .soonestReset: DisplayRepresentation(title: "Soonest Reset First", subtitle: "Whatever resets next")
    ]

    var sort: MobileProviderSort {
        switch self {
        case .yourOrder: .custom
        case .leastLeft: .lowestRemaining
        case .soonestReset: .soonestReset
        }
    }
}

enum OverviewRowCount: String, AppEnum, CaseIterable {
    case automatic
    case one
    case two
    case three
    case four
    case five
    case six

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Rows")
    static let caseDisplayRepresentations: [OverviewRowCount: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "Automatic", subtitle: "As many as this size fits"),
        .one: "1",
        .two: "2",
        .three: "3",
        .four: "4",
        .five: "5",
        .six: "6"
    ]

    /// `nil` means "fill the widget". A number larger than the size can show is trimmed to what fits.
    var requested: Int? {
        switch self {
        case .automatic: nil
        case .one: 1
        case .two: 2
        case .three: 3
        case .four: 4
        case .five: 5
        case .six: 6
        }
    }
}

enum OverviewRowDetail: String, AppEnum, CaseIterable {
    case compact
    case standard
    case expanded

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Row Detail")
    static let caseDisplayRepresentations: [OverviewRowDetail: DisplayRepresentation] = [
        .compact: DisplayRepresentation(title: "Compact", subtitle: "Name and number only, so more providers fit"),
        .standard: DisplayRepresentation(title: "Standard", subtitle: "Name, number, and a bar"),
        .expanded: DisplayRepresentation(title: "Expanded", subtitle: "Adds this provider's other metrics")
    ]
}
