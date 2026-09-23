# Developer guide — Mentra Scanner

This document is for engineers building, extending, or shipping **Mentra Scanner**. User-facing steps live in [README.md](README.md). Mentra-specific integration is in [SDK.md](SDK.md).

**License:** Our original work — Apache 2.0 — **M.R. Dula Enterprise, LLC** ([LICENSE](LICENSE)). Third-party attributions and distribution notes: [NOTICE](NOTICE); overview in [README.md § Legal](README.md#legal).

---

## Prerequisites

- macOS with **Xcode 15+**
- **Apple Developer** account (device signing)
- Physical **iPhone** (iOS 16+)
- **Mentra Live** hardware for end-to-end testing
- **Homebrew** (optional, for `xcodegen`)

---

## Build & run

### Standard path

```bash
cd MentraQR
open MentraQR.xcodeproj
```

1. Select the **MentraQR** scheme and your iPhone.
2. **Product → Run** (⌘R).

The **Install GStreamer iOS SDK** build phase runs `scripts/setup-gstreamer-ios.sh` on first build. GStreamer installs under `~/Library/Developer/GStreamer/iPhone.sdk`.

### XcodeGen (optional)

`MentraQR/project.yml` is the source of truth for target settings, SPM package pin, and signing team placeholder.

```bash
cd MentraQR
xcodegen generate
open MentraQR.xcodeproj
```

After changing `project.yml`, regenerate and commit both `project.yml` and `MentraQR.xcodeproj` if your team uses XcodeGen in CI.

### What does *not* work

- **iOS Simulator** — GStreamer WHIP receiver and device-only link flags; always test on hardware.
- **Embedding GStreamer.framework in the app bundle** — breaks install; static link only (see `project.yml` `OTHER_LDFLAGS`).

---

## Configuration

| Setting | Location | Notes |
|---------|----------|--------|
| Bundle ID | `project.yml` → `PRODUCT_BUNDLE_IDENTIFIER` | Default `com.local.mentraqr` — change for production |
| Display name | `MentraQR/Info.plist` → `CFBundleDisplayName` | **Mentra Scanner** |
| Mentra SDK version | `project.yml` → `packages.MentraBluetoothSDK` | Pin `from: "3.1.1"`; match glasses firmware |
| Deployment target | iOS 16.0 | |
| Wi‑Fi SSID entitlement | `MentraQR.entitlements` | `com.apple.developer.networking.wifi-info` |

Usage strings (Bluetooth, Local Network, Location for SSID) are in `Info.plist`.

---

## Architecture map

```
┌─────────────────┐     BLE      ┌──────────────────┐
│  MentraSession  │◄────────────►│ MentraBluetoothSDK│
│  (orchestrator) │              │  glasses control  │
└────────┬────────┘              └──────────────────┘
         │ startStream(WHIP URL)
         ▼
┌─────────────────┐   BGRA frames   ┌──────────────────┐
│ GStreamerWhip   │────────────────►│ FrameScanDecoder │
│ Receiver + Proxy│                 │ Vision barcodes  │
└─────────────────┘                 │ + Label OCR      │
         │                          └────────┬─────────┘
         │                                   │ snapshot
         ▼                                   ▼
   StreamPreviewView              LabelSnapshotProcessor
                                         │
                                         ▼
                              LabelCaptureLibrary / Store
                                   (JPEG + SQLite)
```

### Key types

| File | Role |
|------|------|
| `MentraSession.swift` | SDK delegate, WHIP lifecycle, Wi‑Fi state, fill light, capture toasts |
| `GStreamerWhipReceiver.m` | WHIP ingest, frame flip for upright pixels, preview + `onFrameImage` |
| `WhipHeaderProxy.swift` | Local WHIP endpoint in front of GStreamer backend port |
| `FrameScanDecoder.swift` | Live decode, auto/manual stream snapshots, cooldowns |
| `LabelSnapshotProcessor.swift` | Full-frame analyze on frozen `CGImage` |
| `LabelCaptureStore.swift` | SQLite persistence |
| `CaptureImageProcessor.swift` | JPEG normalize/trim (glasses photo path + stream frames) |
| `CascadePayloadClassifier.swift` | Heuristics + optional Laya-shaped ML |

### UI shell

| View | Tab / entry |
|------|-------------|
| `ConnectView` | Connect |
| `ScannerView` | Scan |
| `CapturesView` | Captures |
| `SettingsView` | Wi‑Fi, Advanced |
| `LegacyStreamingView` | Advanced → WHIP dev controls |

---

## Debugging

### In-app

Production UI does **not** expose diagnostic consoles. Internal logging still flows through `AppDiagnostics` / `appendDiagnostic` in `MentraSession` for future dev builds.

### Device logs

```bash
./MentraQR/scripts/pull-device-logs.sh
```

Or Console.app → select iPhone → filter `MentraQR` or `com.local.mentraqr`.

### Vision / label tuning

```bash
swift MentraQR/scripts/label_vision_probe.swift /path/to/label.jpg
swift MentraQR/scripts/label_parser_smoke.swift   # if present in scripts
```

Fixture expectations: `MentraQR/scripts/label_sample_expected.json`.

### Laya payload eval (offline, Mac)

```bash
python3 MentraQR/scripts/laya_payload_eval/laya_payload_eval.py
```

See [MentraQR/docs/LAYA_INTEGRATION.md](MentraQR/docs/LAYA_INTEGRATION.md).

---

## Data on disk

Captures live under Application Support (see `LabelCapturePaths` / `CaptureRecord.swift`):

- **Images:** `Application Support/MentraQR/CaptureImages/*.jpg`
- **Database:** `Application Support/MentraQR/captures.sqlite` (label captures + JSON findings)

Deleting the app removes all data.

---

## Coding conventions

- **SwiftUI** for UI; `MentraSession` as `@MainActor` `ObservableObject` environment object.
- **Vision** work off main thread inside `FrameScanDecoder`’s serial queue; publish results on main actor.
- **Capture path:** prefer stream snapshots that do **not** stop WHIP; avoid reintroducing pause/resume photo capture without explicit product approval.
- **High-volume scanning:** respect `snapshotCooldown` / `autoCaptureStableDuration` in `FrameScanDecoder`.
- Keep user-facing copy in **Mentra Scanner** branding (not legacy “Mentra QR”).

---

## Testing checklist (manual)

- [ ] BLE connect / disconnect / reconnect saved device
- [ ] Wi‑Fi provision + SSID match banner
- [ ] Start live → video within ~5s
- [ ] Auto capture on stable QR in guide box
- [ ] Manual Save frame
- [ ] Captures list + detail image orientation correct
- [ ] Stop live → stream tears down, battery reasonable

---

## CI / release (suggested)

Not fully wired in-repo yet; recommended:

1. `xcodebuild -scheme MentraQR -destination 'generic/platform=iOS' build` on Mac runner with GStreamer SDK preinstalled.
2. Archive with production bundle ID and team.
3. Ship [NOTICE](NOTICE) with the binary; record the GStreamer SDK version used in CI and satisfy LGPL static-linking obligations (legal review).

---

## Getting help

- Product direction: [ROADMAP.md](ROADMAP.md)
- Mentra APIs: [SDK.md](SDK.md) and [official Mentra docs](https://docs.mentraglass.com/bluetooth-sdk/overview)
