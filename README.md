# Oyloo App

iOS capture + chat surface for [Oyloo Way](https://github.com/oyloo).

## What it does

A single iOS app + share extension for capturing URLs, photos, files,
and text from any other iOS app. The user defines their own vaults
(name, icon, tint) in the app's settings; the share extension presents
those vaults as picker buttons and routes each share to its
vault-specific outbox.

The container app shows one tab per vault plus a Settings tab for
managing vaults.

## Architecture

```
┌────────────────┐    share-sheet     ┌───────────────────────┐
│  Any iOS app   │ ──────────────►    │ Share Extension       │
└────────────────┘                    │  - extract content    │
                                      │  - vault picker       │
                                      │  - append JSONL       │
                                      └─────────┬─────────────┘
                                                │  App Group
                                                ▼
                                      ┌──────────────────────┐
                                      │ outbox-<key>.jsonl   │
                                      │  (one per vault)     │
                                      └─────────┬────────────┘
                                                │
                                                ▼
                                      ┌──────────────────────┐
                                      │ Container app        │
                                      │  - tab per vault     │
                                      │  - vault management  │
                                      │  - sync (TBD)        │
                                      └──────────────────────┘
```

- **App Group**: `group.com.oyloo.lifeos` — both app and extension
  read/write the same container.
- **Vaults**: user-defined, persisted in App Group `UserDefaults`. Each
  vault has a stable lowercase slug (`key`), a display name, an SF
  Symbol icon, and a tint colour.
- **Outboxes**: `outbox-<vault-key>.jsonl` per vault, append-only,
  one JSON object per line, ISO-8601 timestamps. Future sync workers
  will tail each file and ship to the matching backend endpoint.

## Build

```bash
cd ~/dev/oyloo/oyloo-app
xcodegen
xcodebuild -project LifeOSShare.xcodeproj -scheme LifeOSShare -configuration Debug \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates build

# Install + launch on a connected device:
APP=$(find ~/Library/Developer/Xcode/DerivedData/LifeOSShare-*/Build/Products/Debug-iphoneos -name 'life-os.app' -print -quit)
xcrun devicectl device install app --device <UDID> "$APP"
xcrun devicectl device process launch --device <UDID> com.oyloo.lifeos.app
```

## First-time setup in the app

1. Open the app — it lands on the Settings tab (no vaults yet).
2. Tap **Add your first vault**: choose a display name, slug, SF Symbol,
   and tint.
3. Add as many vaults as you want.
4. Switch to a vault tab to see captures (initially empty).
5. From any other app, share content and pick this app — the picker
   shows your vaults; tap one to save.

## Layout

```
oyloo-app/
├── README.md
├── AGENTS.md  (CLAUDE.md, GEMINI.md → symlinks)
├── project.yml                  # XcodeGen spec
├── .gitignore
├── scripts/                     # private-terms pre-commit hook + installer
└── Sources/
    ├── App/                     # Container app (SwiftUI)
    │   ├── LifeOSShareApp.swift
    │   ├── ContentView.swift
    │   ├── VaultManagementView.swift
    │   ├── Info.plist
    │   └── App.entitlements
    ├── Extension/               # Share extension
    │   ├── ShareViewController.swift
    │   ├── VaultPickerView.swift
    │   ├── Info.plist
    │   └── Extension.entitlements
    └── Shared/                  # App Group shared types
        ├── Vault.swift
        ├── VaultStore.swift
        ├── SharedItem.swift
        ├── SharedStore.swift
        └── ShareLog.swift
```

## Status

Pre-alpha. Bundle id and Xcode project name carry legacy `LifeOSShare`
naming for now; that rename is deferred (it would force re-provisioning
and lose any local data). The app's user-facing identity is **Oyloo Way**.

## License

No license — this repo is private. Targeting eventual public release
(see `AGENTS.md` for the policy that gates public-target commits).
