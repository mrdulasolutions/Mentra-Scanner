# Roadmap — Mentra Scanner

What ships today, what’s in the repo but **off by default**, and what we’re considering next. Timelines are intentional loose — update this file as priorities change.

**Maintainer:** M.R. Dula Enterprise, LLC

---

## Shipped (current product)

| Area | Status | Notes |
|------|--------|--------|
| BLE connect / saved device | ✅ | Connect tab |
| Glasses Wi‑Fi setup | ✅ | Settings → Wi‑Fi |
| Live WHIP preview | ✅ | Scan → Start |
| Multi-symbology barcode scan | ✅ | QR, Code128, PDF417, UPC/EAN, … |
| Label OCR (throttled) | ✅ | Vision text on ROI |
| **Stream-frame capture** | ✅ | Auto + manual Save; WHIP stays up |
| Local Captures (JPEG + SQLite) | ✅ | Captures tab |
| Fill light control | ✅ | Scan toolbar |
| Haptic + on-screen toast feedback | ✅ | No TTS in production UI |
| Payload heuristics + cascade hooks | ✅ | Chips / classification async |
| Upright frame orientation | ✅ | GStreamer flip before save |

---

## In repo, not fully activated

| Feature | Location | How to enable / notes |
|---------|----------|------------------------|
| **Laya Core ML model** | `LayaCoreMLPayloadClassifier.swift` | Bundle `LayaMultilingualANE.mlpackage` (not in repo — large). Without it, keyword stand-in runs. |
| **Full Laya eval pipeline** | `scripts/laya_payload_eval/` | Mac-side; see `docs/LAYA_INTEGRATION.md` |
| **Glasses hi-res photo + webhook** | `LocalPhotoWebhookReceiver.swift` | Legacy; main Scan path does **not** call it |
| **WHIP dev controls** | `LegacyStreamingView.swift` | Settings → Advanced |
| **Pre-capture countdown** | `CaptureCountdown.swift`, `ActivityAnnouncer.runPreCaptureCountdown` | Unused in stream-only UX |
| **Glasses button → capture** | `MentraSession.handleButtonPress` | Stub — reserved |
| **In-app diagnostic console** | `AppDiagnostics`, `diagnosticLines` | Removed from operator UI; logs still append internally |
| **Voice / TTS feedback** | removed | Haptics only — do not re-enable without UX review |

---

## Near-term (planned / high value)

| Item | Rationale |
|------|-----------|
| Production **bundle ID** & signing docs | Move off `com.local.mentraqr` for App Store / enterprise |
| **Export captures** (CSV + images) | Warehouse handoff to WMS/TMS |
| **Configurable scan rates** | Cooldown / stability without code changes |
| **Capture metadata** | Operator ID, site, shift (local or API) |
| **Error surfacing** | Human-readable stream errors in UI (no raw logs) |
| **CI build** | `xcodebuild` + GStreamer cache on runner |

---

## Medium-term

| Item | Notes |
|------|--------|
| **Batch / continuous mode** | Queue scans with minimal UI friction |
| **MDM / managed config** | Wi‑Fi profiles, feature flags |
| **Optional cloud sync** | Encrypted upload; tenant isolation |
| **Android receiver** | Separate client; same WHIP + decode concepts |
| **Deeper carrier parsers** | International formats, GS1 AI fields |
| **Review queue** | Flag suspicious URLs via Laya guardrails in UI |

---

## Long-term / research

| Item | Notes |
|------|--------|
| On-device **fine-tuned** label reader | Custom Vision / Core ML for specific label stock |
| **ERP connectors** | NetSuite, SAP, ShipStation, etc. |
| **Multi-glasses / supervisor** | One phone, many streams (hard) |
| **Offline glasses buffer** | If SDK supports store-and-forward |

---

## Explicit non-goals (for now)

- Cloud-only scanning without local preview
- Breaking WHIP for every capture (reverted hi-res photo path)
- Simulator-first development for video
- Bundling multi-hundred-MB Laya weights in default IPA

---

## How to propose a change

1. Open an issue with **operator story** + **acceptance criteria**.
2. If it touches Mentra SDK version or WHIP ports, update [SDK.md](SDK.md).
3. If it ships dormant code, add a row under **In repo, not fully activated** above.

---

## Version history (app)

| Version | Highlights |
|---------|------------|
| **1.0** | Stream-first Mentra Scanner; Connect / Scan / Captures / Settings |

Update `MARKETING_VERSION` in `MentraQR/project.yml` when releasing.
