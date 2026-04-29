# Oyloo App

iOS capture + chat surface for [Oyloo Way](https://github.com/oyloo). Single Swift app, two backends, shared Rust runtime.

## Position

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  oyloo-life  │  │  oyloo-also  │  │  oyloo-app   │
│  (personal)  │  │  (work/CoC)  │  │  (this repo) │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                 │                  │
       └────────HTTPS────┴────────HTTPS─────┘
                         │
                  ┌──────▼───────┐
                  │  oyloo-core  │
                  │  (Rust libs) │
                  │  Apache 2.0  │
                  └──────────────┘
```

iOS app talks to whichever backend the picker selects (Life endpoint, CoC AI endpoint, CR1 Robotics endpoint). Schema sharing via protobuf (`oyloo-core/oyloo-proto`). No direct dep on Rust core — boundary is the wire format.

## Architecture (current PoC state)

```
┌─────────────────┐    share-sheet      ┌──────────────────────┐
│  YouTube/Safari │ ─────────────────► │ Share Extension      │
└─────────────────┘                    │  - vault picker      │
                                       │  - URL/file/image    │
                                       │  - append JSONL line │
                                       └──────────┬───────────┘
                                                  │  App Group
                                                  ▼
                                       ┌──────────────────────┐
                                       │ outbox-{life,work}   │
                                       │ .jsonl               │
                                       └──────────┬───────────┘
                                                  │
                                                  ▼
                                       ┌──────────────────────┐
                                       │ Container app (UI)   │
                                       │  - tab per vault     │
                                       │  - sync worker (TBD) │
                                       └──────────────────────┘
```

- **App Group**: `group.com.oyloo.lifeos` (will rename to `group.com.oyloo.app`)
- **Outbox**: `<AppGroupContainer>/outbox-{life,work}.jsonl` — append-only, one JSON object per line, ISO-8601 timestamps. Will migrate to protobuf wire format once `oyloo-proto` lands.
- **Bundle IDs (current)**: `com.oyloo.lifeos.app`, `com.oyloo.lifeos.app.share` — rename to `com.oyloo.app` planned in followup.

## Status

Pre-alpha. Migrated from `~/.openclaw/workspace-ed/ios-share-poc/` on 2026-04-29 as part of the Oyloo Way repo restructure. Project name `LifeOSShare` and bundle IDs still carry the PoC names — will rename to `Oyloo` / `com.oyloo.app` in a follow-up commit once the broader sync architecture is specced.

## Build

```bash
cd ~/dev/oyloo/oyloo-app
xcodegen
xcodebuild -project LifeOSShare.xcodeproj -scheme LifeOSShare -configuration Debug \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build

# Install + launch on physical device
APP=$(find ~/Library/Developer/Xcode/DerivedData/LifeOSShare-*/Build/Products/Debug-iphoneos -name 'life-os.app' -print -quit)
xcrun devicectl device install app --device <UDID> "$APP"
xcrun devicectl device process launch --device <UDID> com.oyloo.lifeos.app
```

## Layout

```
oyloo-app/
├── README.md
├── project.yml                  # XcodeGen spec
├── .gitignore
└── Sources/
    ├── App/                     # Container app (SwiftUI)
    │   ├── LifeOSShareApp.swift
    │   ├── ContentView.swift
    │   ├── Info.plist
    │   └── App.entitlements
    ├── Extension/               # Share extension (no-UI + picker)
    │   ├── ShareViewController.swift
    │   ├── VaultPickerView.swift
    │   ├── Info.plist
    │   └── Extension.entitlements
    └── Shared/                  # App Group shared types
        ├── SharedItem.swift
        ├── SharedStore.swift
        └── ShareLog.swift
```

## License

No public license yet — this repo is private. License decision deferred to next architecture pass.
