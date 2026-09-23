# SDK integration — Mentra Scanner

How **Mentra Scanner** uses the **Mentra Bluetooth SDK** and what we added on top (WHIP video, Vision, local storage). This is the “bolt-on” layer future apps can copy or extract.

Official Mentra reference: [Bluetooth SDK overview](https://docs.mentraglass.com/bluetooth-sdk/overview).

**Package pin:** `MentraBluetoothSDK` from `https://github.com/Mentra-Community/mentra-bluetooth-sdk-ios.git` at **3.1.1+** (`MentraQR/project.yml`).

---

## Responsibility split

| Layer | Owner | Responsibility |
|-------|--------|----------------|
| Glasses OS + radio | Mentra | Camera, encode, WHIP publish, Wi‑Fi, BLE protocol |
| `MentraBluetoothSDK` | Mentra Community | Swift API: connect, Wi‑Fi, `startStream` / `stopStream`, display, LEDs, photos |
| **Mentra Scanner bolt-ons** | This repo | WHIP **receive** on iPhone, frame decode, capture DB, operator UI |

We do **not** fork the Mentra SDK. We consume it via Swift Package Manager and wrap it in `MentraSession`.

---

## Core SDK surface we use

Implementation hub: `MentraQR/MentraQR/MentraSession.swift`.

### Connection & state

- `MentraBluetoothSDK` + `MentraBluetoothSDKDelegate`
- `connect(to:)`, `disconnect()`
- `didUpdateGlasses` → battery, Wi‑Fi status, connection
- Persist last device in `UserDefaults` (`mentraqr.defaultDevice.*`)

### Wi‑Fi

- `requestWifiScan()`, provision SSID/password from UI (`WiFiSetupView`)
- Phone SSID via `WiFiSSIDReader` + Location permission (entitlement in `MentraQR.entitlements`)
- `PhoneNetworkInfo.compareNetworks` → `wifiNetworkMatch` for operator banner

### Live video (WHIP)

**Outbound (glasses → phone):** SDK

1. Phone picks LAN IP (`bestLocalIPv4Address()`).
2. `startPhoneReceiver` starts **GStreamer** `whipserversrc` + **WhipHeaderProxy** on ports `8190→8191` (with fallbacks).
3. `publicWhipURL` = `http://<phone-ip>:<port>/whip/endpoint`
4. `sdk.startStream(whipUrl:streamId:)` — glasses publish to that URL.

**Inbound (decode on phone):** our code

- `GStreamerWhipReceiver` → `onFrameImage` → `FrameScanDecoder.process`
- Vertical flip in `GSCreateVerticallyFlippedCopy` so UIKit + JPEG match real-world orientation.

**Stop:** `sdk.stopStream()`, tear down proxy/receiver, `frameScanDecoder.reset()`.

### Gallery mode

- `setGalleryModeEnabled(false)` once per session so button events / app routing behave for scanning (`ensureGalleryModeOff`).

### Glasses display (optional / light use)

- `updateGlassesDisplay(for:)` pushes short summaries of visible codes (length-limited). Not required for capture path.

### Fill light (RGB LED)

- `GlassesFillLight` + SDK RGB LED requests in `MentraSession`
- User toggle on Scan toolbar; keepalive while on

### Button events

- `handleButtonPress` — reserved; short press does not trigger capture (stream auto-capture only today).

---

## Bolt-on modules (not in Mentra SDK)

### 1. WHIP receiver stack

| Component | File |
|-----------|------|
| GStreamer pipeline | `GStreamerWhipReceiver.m` |
| WHIP header proxy | `WhipHeaderProxy.swift` |
| GStreamer iOS bootstrap | `gst_ios_init.m`, `scripts/setup-gstreamer-ios.sh` |

Derived from Mentra starter-kit patterns; adapted for **1080p BGRA appsink**, frame callback to Swift, and orientation fix.

### 2. Scan & capture pipeline

| Component | File |
|-----------|------|
| Live barcode + OCR | `FrameScanDecoder.swift`, `LabelTextRecognizer.swift` |
| Frozen-frame analyze | `LabelSnapshotProcessor.swift` |
| Shipping heuristics | `ShippingBarcodeParser.swift`, `BarcodePayloadNormalizer.swift` |
| ROI / guide overlay | `LabelScanROI.swift`, `LabelGuideOverlay.swift` |
| Persistence | `LabelCaptureLibrary.swift`, `LabelCaptureStore.swift` |

**Product default:** auto + manual capture save a **stream frame** (`captureStreamFrameNow` / `scheduleLabelSnapshotIfNeeded`). WHIP stays running.

### 3. Payload classification (post-decode)

| Component | File |
|-----------|------|
| Rules | `HeuristicPayloadClassifier` in `PayloadClassifier.swift` |
| Cascade | `CascadePayloadClassifier.swift` |
| Laya-shaped ML / stand-in | `LayaCoreMLPayloadClassifier.swift` |

Runs after findings are recorded; powers chips in UI, not barcode reading.

### 4. Legacy / inactive SDK paths (still in tree)

| Component | File | Status |
|-----------|------|--------|
| Glasses JPEG webhook | `LocalPhotoWebhookReceiver.swift` | **Not used** on Scan tab; kept for experiments |
| Hi-res photo + WHIP pause | removed from main flow | See [ROADMAP.md](ROADMAP.md) |
| Countdown capture | `CaptureCountdown.swift` | **Unused** in stream-only flow |

---

## Typical sequence diagram (Scan tab)

```
Operator          MentraSession          SDK              GStreamer
   |                  |                  |                    |
   |-- Start live --->|                  |                    |
   |                  |-- start receiver -------------------->|
   |                  |-- startStream(WHIP URL) ->|          |
   |                  |                  |--- WHIP video --->|
   |                  |<-- onFrameImage ---------------------|
   |                  |-- FrameScanDecoder                    |
   |<-- toast/haptic -| (auto snapshot)                     |
   |                  |-- LabelCaptureStore.save              |
```

---

## Extending the SDK layer safely

1. **Add SDK calls only in `MentraSession`** (or a thin `MentraSDKAdapter` if the file grows).
2. **Never block the main actor** on `startStream` / network; use existing `Task` patterns.
3. **Frame processing** stays in `FrameScanDecoder` queue; UI reads `@Published` outputs only.
4. New hardware features (e.g. gallery photos) should be **feature-flagged** and documented in [ROADMAP.md](ROADMAP.md).
5. Respect Mentra SDK version pins — bump `project.yml` and re-test WHIP when upgrading.

---

## Related docs

- [DEVELOPER.md](DEVELOPER.md) — build, debug, file map
- [MentraQR/docs/LAYA_INTEGRATION.md](MentraQR/docs/LAYA_INTEGRATION.md) — optional Laya / Core ML
- [NOTICE](NOTICE) — third-party licenses
