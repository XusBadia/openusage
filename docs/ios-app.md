# iOS Companion

`Mobile/` contains an iOS 18 SwiftUI companion and two WidgetKit widgets. The app shows provider quotas,
reset times, recent token and cost history, source freshness, and the Macs publishing data. It reads data
from iCloud and never contacts a provider.

The Mac app publishes mobile status only after the user enables **Share Usage With Mobile Devices** in
OpenUsage Settings. History sync and mobile status sharing use separate consent switches. See
[iCloud sync](icloud-sync.md) for the stored fields and privacy boundary.

## Project layout

- `Mobile/project.yml` is the source for the Xcode project.
- `Mobile/App/` contains the iPhone and iPad app.
- `Mobile/Widgets/` contains a configurable small provider widget and a medium overview widget. Provider
  visibility and order are stored in the App Group, so the app and both widgets use the same selection.
- `Sources/OpenUsageMobileCore/` contains the shared document contract and resolvers.
- `Mobile/Config/` contains build identifiers and entitlements.

Run XcodeGen after changing targets, resources, plist values, or entitlements:

```bash
cd Mobile
xcodegen generate --spec project.yml
open UsageCompanion.xcodeproj
```

The checked-in project lets contributors open the app without installing XcodeGen. Keep it in sync with
`project.yml`.

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

Enable iCloud Documents and App Groups for both App IDs in the Apple Developer portal. Assign the iCloud
container to the app App ID. Assign the App Group to the app and widget App IDs. Xcode then creates or
updates the provisioning profiles.

The Mac and iOS builds must use the same iCloud container to exchange files. A third-party TestFlight can
use its own container, bundle IDs, App Group, signing team, display name, and icon. The OpenUsage
maintainers can point an authorized build at the official identifiers and branding.

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
