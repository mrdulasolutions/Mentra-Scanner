# Mentra Scanner

**Mentra Scanner** is an iPhone app for **Mentra Live** smart glasses. It connects over Bluetooth, receives live video over **Wi‑Fi (WHIP/WebRTC)**, and automatically saves **stream frames** when QR codes and shipping barcodes sit in view—plus parsed label fields—on device.

Licensed under **Apache 2.0** by [M.R. Dula Enterprise, LLC](LICENSE).

---

## What you need

| Item | Notes |
|------|--------|
| **iPhone** | iOS 16+, physical device (not Simulator—video stack requires device) |
| **Xcode** | 15+ recommended |
| **Mentra Live glasses** | Firmware aligned with [Mentra Bluetooth SDK](https://docs.mentraglass.com/bluetooth-sdk/overview) **3.1.1+** (see `MentraQR/project.yml`) |
| **Wi‑Fi** | Phone and glasses on the **same network**; no AP client isolation blocking phone ↔ glasses |

First Xcode build downloads the **GStreamer iOS SDK** via `MentraQR/scripts/setup-gstreamer-ios.sh`. The app links GStreamer **statically**—do not embed `GStreamer.framework` in the bundle.

---

## Quick start (operators)

1. **Install** the app on your iPhone (Xcode → Run, or your MDM/TestFlight flow).
2. Open **Connect** → pair your glasses.
3. Open **Settings → Wi‑Fi** → put glasses on the same network as the phone; confirm the match banner is green.
4. Open **Scan** → tap **Start** for live view.
5. Point at a **QR or barcode** in the on-screen guide; captures save automatically (toast + haptic). Full history is under **Captures**.

**Bottom bar on Scan**

| Button | Action |
|--------|--------|
| **Start / Stop** | Begin or end live WHIP scanning |
| **Save** | Save the current frame manually |
| **Clear** | Clear the on-screen “last capture” preview (files in Captures stay) |

**Toolbar:** fill light toggle (glasses RGB LED when supported).

---

## Quick start (developers)

```bash
cd MentraQR
brew install xcodegen   # optional; repo includes MentraQR.xcodeproj
xcodegen generate       # refresh project from project.yml if you changed it
open MentraQR.xcodeproj
```

Select your **Development Team** in Xcode (or set `developmentTeam` in `MentraQR/project.yml` and regenerate).

Build and run on a **connected iPhone**.

More detail: [DEVELOPER.md](DEVELOPER.md) · Mentra integration: [SDK.md](SDK.md) · Plans: [ROADMAP.md](ROADMAP.md)

---

## How it works (one paragraph)

The phone runs a local **WHIP receiver** (GStreamer + header proxy). The Mentra SDK **`startStream`** sends glasses video to that endpoint. Each frame is decoded with **Apple Vision** (barcodes + OCR), auto-saved through **`FrameScanDecoder`** / **`LabelSnapshotProcessor`**, and stored as **JPEG + SQLite** via **`LabelCaptureStore`**. The live stream **stays up** during capture—no glasses still-photo pipeline on the main path.

---

## Repository layout

```
.
├── LICENSE / NOTICE          # Apache 2.0 — M.R. Dula Enterprise, LLC
├── README.md                 # You are here
├── DEVELOPER.md              # Build, debug, conventions
├── SDK.md                    # Mentra SDK + our bolt-ons
├── ROADMAP.md                # Shipped vs planned
└── MentraQR/
    ├── MentraQR/             # iOS app sources
    ├── scripts/              # GStreamer setup, Vision probes, Laya eval
    ├── docs/                 # Deep dives (e.g. Laya)
    └── project.yml           # XcodeGen spec
```

---

## Privacy

Scan images and parsed fields are stored **locally** in the app’s Application Support directory. Nothing is uploaded by default.

---

## Support & contributions

- Bugs and features: use your team’s issue tracker (GitHub Issues when this repo is published).
- See [DEVELOPER.md](DEVELOPER.md) for logging, scripts, and code map.
- External SDKs: [NOTICE](NOTICE).
