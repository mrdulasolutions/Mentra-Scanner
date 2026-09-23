# Third-party licenses

Components used by **Mentra Scanner** that are **not** exclusively copyrighted by M.R. Dula Enterprise, LLC. When you ship a binary, you are responsible for **all** rows below, not only our [LICENSE](LICENSE).

---

## Runtime / linked dependencies

| Component | Version (pinned) | How it is obtained | License | Notes |
|-----------|------------------|--------------------|---------|--------|
| **MentraBluetoothSDK** | 3.1.1 ([revision a1d2694…](https://github.com/Mentra-Community/mentra-bluetooth-sdk-ios)) | Swift Package Manager at build | **Apache 2.0** | [LICENSE](https://github.com/Mentra-Community/mentra-bluetooth-sdk-ios/blob/main/LICENSE). Linked into app binary. |
| **GStreamer** (iOS SDK) | Installed by `setup-gstreamer-ios.sh` | Download on developer machine; static link | **LGPL** (verify per your SDK build) | WHIP/video decode. **LGPL compliance required for distribution.** [FAQ](https://gstreamer.freedesktop.org/documentation/frequently-asked-questions/licensing.html). |
| **Apple iOS SDK** | Xcode toolchain | System / Xcode | **Apple SDK / ToS** | SwiftUI, Vision, AVFoundation, CoreBluetooth (via Mentra SDK), etc. |

---

## Repository-only / optional

| Component | Location | License | Notes |
|-----------|----------|---------|--------|
| **Laya** (referenced) | `MentraQR/docs/LAYA_INTEGRATION.md`, `scripts/laya_payload_eval/` | **Apache 2.0** (upstream) | Eval tooling; optional Core ML bundle not included. |
| **Mentra starter-kit patterns** | WHIP receiver lineage (see `SDK.md`) | Per upstream | Our modified files are under project [LICENSE](LICENSE). |

---

## Mentra Bluetooth SDK — Apache 2.0 notice

The app imports `MentraBluetoothSDK` from:

`https://github.com/Mentra-Community/mentra-bluetooth-sdk-ios.git`

Copyright and license terms are those of the Mentra Community and its contributors, under the **Apache License, Version 2.0**. A copy of the Apache 2.0 license applies to the SDK source; our [LICENSE](LICENSE) applies to **this repository’s original files**, not to a re-license of the SDK itself.

---

## GStreamer — distribution reminder

Static linking of LGPL libraries into an iOS app typically requires you to:

- Provide **license texts** for GStreamer and dependent libraries to recipients as LGPL requires.
- Enable users to **replace or relink** the LGPL-covered library where applicable (mechanisms vary for iOS; **consult counsel**).

This repository does **not** embed GStreamer source; it documents installation via script. Your CI/release process must record **which GStreamer version** was linked.

---

## Updating this file

When you add SPM packages, vendored libraries, or embedded models, add a row here and extend [NOTICE](NOTICE).
