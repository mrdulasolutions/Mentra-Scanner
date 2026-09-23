# Laya in MentraQR

[Laya](https://brainfunctioncollapse.com/laya) is an open-source **System 1 decision model** (Apache-2.0, [NandhaKishorM/laya](https://github.com/NandhaKishorM/laya)): you pass **text state** plus **typed questions** (`choice`, `score`, `noul`) and get **probabilities**, not generated chat. It fits **after** QR decode (labeling, routing, guardrails), not instead of Vision barcode detection.

## Ambiguity

“Laya” elsewhere can mean the Laya game engine or other products. This doc is only for **Convai / brain function collapse Laya**.

## Can it run in this iOS app?

| Aspect | Reality |
|--------|---------|
| Official SDK | **Python** (`pip install laya`), PyTorch + Hugging Face weights (~650 MB–2.3 GB per load strategy) |
| Native iOS SDK | **None** from Convai |
| On-device iOS path | Community **[laya-coreml](https://github.com/mizorewww/laya-coreml)** exports `.mlpackage` bundles ([Hugging Face `aac6fef/*`](https://huggingface.co/aac6fef/laya-coreml)); ML Programs target **iOS 18** per upstream docs; **iOS deployment is not officially tested** |
| Where it runs | **iPhone only** in MentraQR — glasses send video; the phone decodes QR and should run Laya on **payload strings** |
| API keys | **Not required** for local weights |
| Size | Plan for **hundreds of MB** in the app or **on-demand download** (App Store / storage impact) |
| Latency | ~5–35 ms per decision on Apple Silicon (Mac benchmarks); phone will be slower on CPU/GPU; ANE variant needs **≤96 tokens total** per call |

## Recommended architecture in MentraQR

```
Glasses camera → WHIP → CGImage frames → Vision (QRFrameDecoder) → payload string
                                                      ↓
                                            PayloadClassifier (async, throttled)
                                                      ↓
                              UI + optional glasses display summary
```

1. **Trigger** when a **new** `ScanFinding` enters session history via `onNewFinding` (not every frame). Classification uses fused `ScanClassificationContext` (barcode text, symbology, parsed carrier, optional OCR excerpt).
2. **Throttle** — one forward pass per payload; debounce re-scans of the same string.
3. **Questions** — ask what the **text says**, not what to do (Laya skill guidance). Example `noul`: “Does this text ask for an urgent payment or credential?” Example `choice`: route to Open / Copy / Review.
4. **Cascade** — if `confidence` or top probability is below a threshold measured on **your** QR samples, show “Review” instead of auto-opening URLs.

`CascadePayloadClassifier` runs `HeuristicPayloadClassifier` first, then `LayaCoreMLPayloadClassifier` for ambiguous payloads and HTTPS guardrails. Embed an optional Core ML bundle named **`LayaMultilingualANE.mlpackage`** in the app target to enable real inference (tokenizer port still required; see `LayaCoreMLPayloadClassifier.swift`).

Tune thresholds with:

```bash
python3 MentraQR/scripts/laya_payload_eval/laya_payload_eval.py
```

`PayloadClassifier.swift` defines question templates in `LayaQRPayloadQuestions`.

## Embedding Core ML (exact steps, no proprietary APIs)

1. **Choose a bundle** (independent port, not Convai-official):
   - General English: `aac6fef/laya-coreml` (512 tokens, CPU+GPU).
   - Short + ANE: `aac6fef/laya-multilingual-coreml-ane` (**96 token** cap including state + questions).
2. **Download** (developer machine):
   ```bash
   pip install huggingface_hub
   hf download aac6fef/laya-multilingual-coreml-ane --local-dir ./laya-ane
   ```
3. **Add to Xcode** — drag the `.mlpackage` into the MentraQR target; use **On Demand Resources** or a first-launch download if you want to avoid a huge initial IPA.
4. **Preprocessing** — replicate `laya-coreml` tokenization and question encoding in Swift (today only implemented in Python). Read [laya-coreml USAGE](https://github.com/mizorewww/laya-coreml/blob/main/docs/USAGE.md) and the upstream `laya` `predict()` format. Do not guess tensor names; inspect the package with Core ML Tools or Xcode.
5. **Inference** — `MLModel` + `MLDictionaryFeatureProvider`; run off the main actor; single-flight queue (one forward pass at a time).
6. **Implement** `PayloadClassifying` in a new `LayaCoreMLPayloadClassifier` and swap the instance in `MentraSession` (search for `HeuristicPayloadClassifier`).
7. **Evaluate** — 50–200 real scanned payloads; tune thresholds; report escalation rate (Laya skill checklist).

## Alternatives (usually worse on-phone)

- **Python sidecar** — fine on Mac (`server.py` on loopback); **not** viable inside a standalone iPhone app.
- **Hosted LLM** — contradicts offline / private QR content unless you accept sending payloads to a vendor.

## Blockers summary

- No drop-in Swift Package from Convai.
- Full Laya on iOS requires **Core ML bundle + tokenizer port** (community exports exist; integration work is real).
- **Deployment target** is iOS 16 today; ANE/general ML Program bundles may require **raising to iOS 18** and device testing.
- **ANE 96-token limit** is tight for long URLs; truncate state (put host + path start first) or use the 512/1024 GPU bundle.

## References

- [Laya overview](https://brainfunctioncollapse.com/laya)
- [Integration skill (Python)](https://brainfunctioncollapse.com/laya/skills/laya-integration/SKILL.md)
- [convaiinnovations/laya on Hugging Face](https://huggingface.co/convaiinnovations/laya)
- [laya-coreml](https://github.com/mizorewww/laya-coreml)
