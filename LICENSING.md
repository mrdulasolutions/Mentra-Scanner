# Licensing — Mentra Scanner

This document explains **what M.R. Dula Enterprise, LLC owns**, **what belongs to third parties**, and **what you must do** when you use, modify, or ship this project. It is a guide for humans; the legally operative texts are [LICENSE](LICENSE) (our code) and [NOTICE](NOTICE) (attributions).

---

## Summary

| What | Who | License / terms |
|------|-----|------------------|
| **Original source in this repository** (app code, docs, scripts, assets we added) | M.R. Dula Enterprise, LLC | [Apache License 2.0](LICENSE) |
| **Mentra Bluetooth SDK for iOS** (Swift Package, not vendored in git) | Mentra Community / licensors | [Apache License 2.0](https://github.com/Mentra-Community/mentra-bluetooth-sdk-ios/blob/main/LICENSE) |
| **GStreamer iOS SDK** (downloaded at build time, statically linked) | GStreamer / contributors | **LGPL** (see [GStreamer licensing](https://gstreamer.freedesktop.org/documentation/frequently-asked-questions/licensing.html)) |
| **Apple system frameworks** (SwiftUI, Vision, AVFoundation, etc.) | Apple Inc. | Apple SDK and App Store terms |
| **Optional Laya-related eval scripts** (no model weights in repo) | Various (see script headers) | Apache 2.0 where noted in upstream |

**There is no license conflict** between our Apache 2.0 application code and the Mentra SDK’s Apache 2.0: both allow combination in a commercial app if you preserve notices and comply with each licensor’s terms. **GStreamer LGPL** is the main extra obligation when you **distribute a compiled app** that links it.

---

## What we own (M.R. Dula Enterprise, LLC)

Under [LICENSE](LICENSE), we grant you rights to our **original work** in this repository, including but not limited to:

- Mentra Scanner **application source** under `MentraQR/MentraQR/` (UI, session orchestration, frame capture pipeline, local SQLite capture store, Vision integration layer, WHIP receiver glue, and related helpers).
- **Documentation** in this repo (`README.md`, `DEVELOPER.md`, `SDK.md`, `ROADMAP.md`, `LICENSING.md`, etc.).
- **Build scripts and tooling** under `MentraQR/scripts/` that we authored.
- **Branding** for this product name **“Mentra Scanner”** as used by us (see trademarks below).

**What we do not claim to own:**

- The **Mentra Bluetooth SDK**, Mentra Live glasses firmware, or Mentra’s APIs and documentation.
- **GStreamer** libraries or the upstream WHIP/WebRTC stack inside GStreamer.
- **Apple** platforms, frameworks, or App Store distribution rules.
- Third-party **trademarks** (see below).

Our **ideas and product design** (stream-first QR capture on glasses, bolt-on architecture described in `SDK.md`, etc.) are part of our project; copying or cloning them may still be subject to patent, trademark, and contract law outside of copyright licenses. The Apache License covers **copyright in our code**, not unlimited use of others’ brands or SDKs.

---

## Third parties you must respect

### Mentra Bluetooth SDK

- **Fetched via Swift Package Manager** at build time (`MentraQR/project.yml` pins version **3.1.1**).
- **License:** Apache 2.0 (same family as our license).
- **You must:** keep Mentra’s copyright and license notices for the SDK when required by Apache 2.0; follow [Mentra’s official SDK documentation](https://docs.mentraglass.com/bluetooth-sdk/overview) and any separate **Mentra developer / hardware terms** that apply to your use of glasses and APIs.
- **Trademark:** “Mentra”, “Mentra Live”, and related marks are **not** owned by M.R. Dula Enterprise, LLC. This project is a **compatible client**, not an official Mentra product, unless you have a separate agreement stating otherwise.

### GStreamer

- **Installed** by `MentraQR/scripts/setup-gstreamer-ios.sh` into your Mac (not committed to git).
- **Linked statically** into the iOS binary for WHIP video receive.
- **License:** LGPL (typically LGPL 2.1 for core libraries — confirm against your installed SDK version).
- **You must:** if you **distribute** the app to users, comply with LGPL requirements (including making corresponding source or object files available as required, and providing license text). **Get legal review** before App Store or enterprise distribution. See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

### Apple

- The app targets **iOS** and uses **system frameworks**. Distribution is subject to the **Apple Developer Program License Agreement** and App Store rules.

### Optional / development-only

- **Laya** eval scripts and docs reference Apache-2.0 upstream; **Core ML model weights are not shipped** in this repository by default.
- **Starter-kit lineage:** WHIP receiver patterns may derive from Mentra community examples; our files are licensed under our [LICENSE](LICENSE) for our contributions; upstream remains under its own terms.

---

## Trademarks

- **Mentra Scanner** — product name used by M.R. Dula Enterprise, LLC for this software.
- **Mentra**, **Mentra Live**, and related logos — property of their respective owners. Use only to describe compatibility (“works with Mentra Live glasses”), not to imply endorsement without permission.

---

## If you fork or ship a binary

1. **Keep** [LICENSE](LICENSE) and [NOTICE](NOTICE) (and update [NOTICE](NOTICE) if you add dependencies).
2. **Do not** remove Mentra SDK or GStreamer attributions.
3. **Comply** with LGPL for GStreamer if you distribute linked binaries.
4. **Do not** represent your fork as official Mentra software without authorization.
5. **Consider** a privacy policy if you handle user data; captures in this app are **on-device by default**.

---

## Questions

For **our code** (Apache 2.0): see [LICENSE](LICENSE).

For **Mentra SDK**: Mentra Community / [mentra-bluetooth-sdk-ios](https://github.com/Mentra-Community/mentra-bluetooth-sdk-ios).

For **legal advice** on LGPL compliance or commercial distribution: consult your counsel; this document is not legal advice.
