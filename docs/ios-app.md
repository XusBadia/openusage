# iOS Companion

`Mobile/` contains an iOS 18 SwiftUI companion and two WidgetKit widgets. The app shows provider quotas,
reset times, recent token and cost history, source freshness, and the Macs publishing data. It reads data
from iCloud and never contacts a provider.

When both apps belong to the same Apple team, the Mac app can publish directly after the user enables
**Share Usage With Mobile Devices** in OpenUsage Settings. The maintainer's TestFlight build instead uses
the signed **OpenUsage Mobile Bridge**: it reads the official Mac app's read-only loopback API and writes
the same sanitized document into the companion's iCloud container. See [iCloud sync](icloud-sync.md) for
the stored fields and privacy boundary.

## Project layout

- `Mobile/project.yml` is the source for the Xcode project.
- `Mobile/App/` contains the iPhone and iPad app.
- `Mobile/Widgets/` contains a configurable provider widget (small and medium) and an overview widget
  (medium and large). Provider and metric choices are stored in the App Group, so the app and both
  widgets use the same selection.
- `Sources/OpenUsageMobileCore/` contains the shared document contract, the resolvers, and the iCloud
  reader the app and the widgets both run.
- `Sources/OpenUsageMobileBridgeCore/` maps the official app's local API to that mobile contract and
  publishes it to the TestFlight container.
- `Sources/OpenUsageMobileBridge/` is the small macOS menu-bar process that runs that sync every five
  minutes.
- `Mobile/Config/` contains build identifiers and entitlements.

Run XcodeGen after changing targets, resources, plist values, or entitlements:

```bash
cd Mobile
xcodegen generate --spec project.yml
open UsageCompanion.xcodeproj
```

The checked-in project lets contributors open the app without installing XcodeGen. Keep it in sync with
`project.yml`.

## Staying current

The app reads iCloud when it opens and whenever it returns to the foreground. **The widgets read iCloud
themselves** on each timeline refresh, so a widget keeps updating even if nobody opens the app; iOS
budgets those refreshes, so expect a widget to be current within roughly 15 to 60 minutes rather than
matching the Mac's five-minute cycle minute for minute.

Relative reset and update times keep two useful units in the app (`1h 20m`). Home Screen widgets use a
single unit (`1h`) where the same text has much less room.

Whichever surface refreshed last writes the App Group cache, and the others render that cache while their
own read is in flight. A failed read never blanks a widget: it keeps showing the last values it had and
records the reason in the log.

Both the app and the widget extension therefore need the iCloud container in their entitlements and in
their provisioning profiles.

## Choosing what each provider shows

**Settings › Providers** decides what appears and how much of it, for the app and for both widgets:

- Tap a provider to open its own screen. Tap **Edit** on either screen to drag rows into a new order.
- **Show This Provider** removes it from Today and from the widgets. Nothing is deleted — the Mac keeps
  publishing it and it can be shown again at any time.
- **Card Detail** sets how many metrics fit under the headline on a card: Compact shows the headline
  alone, Standard adds two more, Detailed adds every metric that is still visible.
- The **Metrics** list turns individual metrics on and off and orders them. The first visible metric is
  the headline on the Today card, in the overview widget row, and in the provider widget. A provider
  always keeps at least one visible metric, so a card never goes blank.
- A provider's detail screen still lists hidden metrics under **Hidden Metrics**, so a number is never
  more than a tap away.
- **Reset Every Provider** restores every provider and metric, in the order the Mac publishes them.

## Configuring a widget on the Home Screen

Both widgets follow the app's choices by default. Long-press one and choose **Edit Widget** to give that
copy its own settings, so two widgets of the same kind can watch different things.

**Provider Usage** (small, medium):

- **Provider** — which provider it shows.
- **Metric** — which metric it leads with. Only metrics kept visible in the app are offered; if the chosen
  one is later hidden, it falls back to the provider's headline metric.

**Usage Overview** (medium, large):

- **Providers** — leave empty to follow the app, or pick the ones this widget should list. A provider
  hidden in the app never appears, whatever is picked here.
- **Order** — Your Order, Least Left First (whatever is closest to running out), or Soonest Reset First.
  The last two sort on each provider's headline metric, so reordering metrics in the app changes what they
  compare.
- **Rows** — Automatic fills the widget; a number smaller than that shows fewer. A number larger than the
  size can fit is trimmed to what fits.
- **Row Detail** — Compact (name and number, so more providers fit), Standard (adds a bar), or Expanded
  (adds that provider's other visible metrics).
- **Show Title**, **Show Reset Times**, **Show Plan Names** — turn off what you do not need. Reset times
  need Standard or Expanded to have room.

## Local identifiers

The repository defaults to neutral development identifiers and the official **OpenUsage** product name.
Copy the example file and enter values owned by your Apple Developer team:

```bash
cd Mobile/Config
cp Local.xcconfig.example Local.xcconfig
```

Set these values in `Local.xcconfig`:

- `MOBILE_APP_BUNDLE_ID` for the App Store Connect app.
- `MOBILE_WIDGET_BUNDLE_ID` for the widget extension.
- `MOBILE_DEVELOPMENT_TEAM` for signing.
- `ICLOUD_CONTAINER_IDENTIFIER` for the shared iCloud Documents container.
- `APP_GROUP_IDENTIFIER` for the app-to-widget cache.

Enable iCloud Documents and App Groups for both App IDs in the Apple Developer portal, and assign the
iCloud container **and** the App Group to both the app and the widget App IDs — the widget extension reads
iCloud on its own, so a profile without the container makes its timelines fall back to the cache forever.
Xcode then creates or updates the provisioning profiles.

The process that writes the companion document and the iOS build must use the same iCloud container. If
the official Mac app is signed by a different Apple team, install the bridge signed by the companion's
team instead of replacing or re-signing OpenUsage. A third-party TestFlight can use its own container,
bundle IDs, App Group, signing team, display name, and icon.

## Mac bridge

The bridge leaves `/Applications/OpenUsage.app` untouched, so Sparkle continues to update the official
Mac app. It contacts only `http://127.0.0.1:6736`, publishes no credentials or raw provider responses,
and starts at login. Build and install the maintainer configuration with:

```bash
./script/build_mobile_bridge.sh install
```

The installed Developer ID profile must allow `me.badia.ailimits.collector` and
`iCloud.me.badia.ailimits`. The menu-bar phone icon shows the last sync result and offers **Sync Now**.
If OpenUsage's history sync is enabled, compatible history documents are mirrored as well; quota and
balance updates do not depend on history sync.

## Build and test

Use the full Xcode developer directory if `xcode-select` points at Command Line Tools:

```bash
cd Mobile
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project UsageCompanion.xcodeproj \
  -scheme UsageCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

Run shared contract tests from the repository root:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --filter OpenUsageMobileCoreTests
```

Pass `-ui-preview` when launching the simulator build to use deterministic Claude and Codex fixtures.
Add `-preview-tab history` or `-preview-tab settings` to capture those screens. Production builds ignore
the preview path unless the process receives the explicit argument. Add `-preview-providers` to open the
provider visibility and ordering screen directly for visual QA.

## TestFlight and branding

Each publisher creates its own App Store Connect app and uploads a build signed by its Apple Developer
team. The bundle ID ties that build to the App Store Connect record. TestFlight does not require the
upstream maintainers to share our record or certificates.

The source code uses the MIT license. `TRADEMARK.md` reserves the OpenUsage name and logo, so third-party
publishers must replace the default product identity or obtain permission. The default name and icon are
ready for the OpenUsage maintainers to use in an official build.

The `iOS TestFlight` GitHub Actions workflow archives, validates, and uploads the app. Configure these
secrets in the repository that runs the workflow:

- `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64`
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `IOS_APP_PROFILE_BASE64`
- `IOS_WIDGET_PROFILE_BASE64`
- `APP_STORE_CONNECT_API_KEY_P8_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

Every run uses the GitHub run number as `CFBundleVersion`, so TestFlight receives a distinct update. Use
the manual workflow input to choose the user-facing version; the default is `0.1.0`. Distribution IDs and
profile names live in `Mobile/Config/TestFlight.xcconfig`, and export settings live in
`Mobile/Config/ExportOptions-TestFlight.plist`.
