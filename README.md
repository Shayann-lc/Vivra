# Vivra

An on-device lifestyle coach for iOS. It finds patterns across sleep, heart,
activity, mood and nutrition data and explains them in plain language. All data
stays on the device.

- Plan and architecture: [`docs/PLAN.md`](docs/PLAN.md)
- Writing rules: [`docs/STYLE_GUIDE.md`](docs/STYLE_GUIDE.md)
- Device test steps: [`docs/DEVICE_TEST.md`](docs/DEVICE_TEST.md)
- Not medical advice. Vivra describes observed patterns only.

## Requirements

- Xcode 26 (iOS 26 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46.0 (`brew install xcodegen`)

## Getting started

```sh
xcodegen generate        # creates Vivra.xcodeproj (not committed)
open Vivra.xcodeproj
```

Simulator builds work out of the box. To run on a device, copy
`Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your bundle
ID and team.

## Layout

```
App/                 SwiftUI app target
AppTests/            Tests hosted in the app (real Keychain)
Packages/VivraCore   Model, sync engine, insight engine, narrative rules; tests on Linux too
Packages/VivraStore  Encrypted store: GRDB + SQLCipher, key in the Keychain
Packages/HealthSync  HealthKit adapter (anchored queries, background delivery)
Packages/Narrative   On-device Foundation Models narrator
Vendor/GRDB          GRDB.swift built against SQLCipher (see VENDORED.md)
Config/              xcconfig files
scripts/             Guard checks, vendoring, CI helpers
```

## Checks

```sh
scripts/check-guards.sh                                      # privacy/determinism rules
swift format lint --strict --recursive App AppTests Packages # formatting
swift test --package-path Packages/VivraCore                 # core tests (macOS or Linux)
xcodebuild test -project Vivra.xcodeproj -scheme Vivra \
  -destination "$(scripts/sim-destination.sh)"              # everything, on a simulator
```

CI runs all of these on every push to `main` and on pull requests.
