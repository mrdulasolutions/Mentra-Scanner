import CoreGraphics
import Foundation
import Vision

typealias QRDetection = ScanFinding

@MainActor
final class FrameScanDecoder: ObservableObject {
    @Published private(set) var visibleFindings: [ScanFinding] = []
    @Published private(set) var lastScanDebugLine = ""
    @Published private(set) var labelCaptureStatus = ""
    @Published private(set) var activeLabelROI: CGRect = LabelScanROI.defaultGuide
    @Published private(set) var labelROITracksBarcodes = false

    var visibleCodes: [ScanFinding] { visibleFindings }

    private let queue = DispatchQueue(label: "com.local.mentraqr.scan", qos: .userInitiated)
    private let ocr = LabelTextRecognizer()
    private var lastBarcodeProcessTime = Date.distantPast
    private let barcodeMinInterval: TimeInterval = 1.0 / 5.0
    private let missingThreshold: TimeInterval = 2.5
    /// Min time between stream-frame saves (high-volume scanning).
    private let snapshotCooldown: TimeInterval = 3.5
    /// Code must sit in the guide this long before auto-save.
    private let autoCaptureStableDuration: TimeInterval = 0.5
    private let autoCaptureCooldown: TimeInterval = 3.5
    private var labelROIGreenSince: Date?
    private var denseLabelTextSince: Date?
    private var tracksBarcodesInFrame = false
    private var lastAutoCaptureTime = Date.distantPast
    private var autoCapturePending = false
    @Published private(set) var isStreamSnapshotInFlight = false
    private var scannableCodeInFrame = false
    private var tracking: [String: ScanFinding] = [:]
    private var framesProcessed = 0
    private var lastDebugPublish = Date.distantPast
    private var lastLabelSnapshotTime = Date.distantPast
    private var labelSnapshotInFlight = false
    private var labelOCREnabled = false

    var onVisibleSetChanged: (([ScanFinding]) -> Void)?
    var onNewFinding: ((ScanFinding) -> Void)?
    var onScanDebug: ((String) -> Void)?
    var onLabelSnapshotCaptured: ((CGImage, [ScanFinding], String, Data?, CGRect) -> Void)?
    var onStreamSnapshotSaved: ((Int) -> Void)?

    func reset() {
        ocr.reset()
        tracking.removeAll()
        visibleFindings = []
        framesProcessed = 0
        lastScanDebugLine = ""
        labelCaptureStatus = ""
        lastLabelSnapshotTime = Date.distantPast
        labelSnapshotInFlight = false
        activeLabelROI = LabelScanROI.defaultGuide
        labelROITracksBarcodes = false
        labelROIGreenSince = nil
        denseLabelTextSince = nil
        tracksBarcodesInFrame = false
        autoCapturePending = false
        scannableCodeInFrame = false
        onVisibleSetChanged?([])
    }

    func noteAutoCaptureFinished() {
        queue.async { [weak self] in
            guard let self else { return }
            lastAutoCaptureTime = Date()
            lastLabelSnapshotTime = Date()
            autoCapturePending = false
            labelROIGreenSince = nil
            Task { @MainActor in
                self.isStreamSnapshotInFlight = false
            }
        }
    }

    func cancelPendingAutoCapture() {
        queue.async { [weak self] in
            self?.autoCapturePending = false
        }
    }

    func setLabelOCREnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            labelOCREnabled = enabled
            if !enabled {
                ocr.reset()
                tracking = tracking.filter { $0.value.source != .ocr }
                publishVisible()
            }
        }
    }

    /// Saves the latest live frame + parsed fields (no glasses photo, WHIP stays up).
    func captureStreamFrameNow(reason: String = "manual capture") {
        queue.async { [weak self] in
            guard let self else { return }
            scheduleLabelSnapshotIfNeeded(
                image: pendingSnapshotFrame,
                reason: reason,
                now: Date(),
                bypassCooldown: true
            )
        }
    }

    /// Manual Scan button: full barcode + OCR on a frozen frame; saves via `onLabelSnapshotCaptured`.
    func ingestManualCapture(
        image: CGImage,
        findings: [ScanFinding],
        originalJPEG: Data?,
        labelROI: CGRect,
        triggerReason: String = "manual Scan"
    ) {
        let frameSize = "\(image.width)×\(image.height)"
        queue.async { [weak self] in
            self?.ingestLabelSnapshotFindings(
                findings,
                frameSize: frameSize,
                image: image,
                triggerReason: triggerReason,
                originalJPEG: originalJPEG,
                labelROI: labelROI
            )
        }
    }

    init() {
        ocr.onDebug = { [weak self] message in
            self?.publishDebug(message)
        }
    }

    private var pendingSnapshotFrame: CGImage?
    private var currentLabelROI = LabelScanROI.defaultGuide

    func process(_ image: CGImage) {
        let now = Date()
        queue.async { [weak self] in
            guard let self else { return }
            pendingSnapshotFrame = image
            detectBarcodes(in: image, at: now)
            guard labelOCREnabled else { return }
            for ocrFinding in ocr.process(image, labelROI: currentLabelROI, now: now) {
                ingestOCRFinding(ocrFinding, at: now)
            }
        }
    }

    private func detectBarcodes(in image: CGImage, at now: Date) {
        guard now.timeIntervalSince(lastBarcodeProcessTime) >= barcodeMinInterval else { return }
        lastBarcodeProcessTime = now
        framesProcessed += 1

        let scaled = VisionFrameScaler.scaledForBarcodeScan(image)
        let request = VNDetectBarcodesRequest()
        request.symbologies = Self.shippingSymbologies
        let handler = VNImageRequestHandler(cgImage: scaled, options: [:])

        do {
            try handler.perform([request])
            let observations = request.results ?? []

            if framesProcessed % 15 == 0 || !observations.isEmpty {
                let sizes = "\(image.width)×\(image.height)→\(scaled.width)×\(scaled.height)"
                let msg = "Vision barcodes: \(observations.count) in frame (\(sizes))"
                publishDebug(msg)
            }

            var seenKeys = Set<String>()
            var updated = tracking

            var frameCandidates: [ScanFinding] = []
            for observation in observations {
                guard let rawPayload = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !rawPayload.isEmpty else {
                    continue
                }
                let symName = observation.symbology.rawValue
                let normalized = BarcodePayloadNormalizer.normalize(rawPayload)
                let parsed = ShippingBarcodeParser.parse(text: rawPayload, symbology: symName)
                let displayText = normalized.isEmpty ? rawPayload : normalized
                let key = parsed?.parcelKey.map { "parcel:\($0)" }
                    ?? ParcelKey.barcodeTrackingKey(symbology: symName, raw: displayText)
                seenKeys.insert(key)
                let finding = ScanFinding(
                    id: key,
                    source: .barcode,
                    symbology: symName,
                    rawText: displayText,
                    boundingBox: observation.boundingBox,
                    lastSeen: now,
                    parsed: parsed
                )
                frameCandidates.append(finding)
            }

            let ranked = frameCandidates.sorted {
                ShippingBarcodeParser.rankingScore(for: $0) > ShippingBarcodeParser.rankingScore(for: $1)
            }
            let barcodeBoxes = frameCandidates.compactMap(\.boundingBox)
            scannableCodeInFrame = frameCandidates.contains { finding in
                let sym = finding.symbology?.lowercased() ?? ""
                return sym.contains("qr") || sym.contains("code") || sym.contains("pdf") || sym.contains("aztec")
                    || sym.contains("data")
            }
            let roi = LabelScanROI.inferred(from: barcodeBoxes)
            currentLabelROI = roi
            publishLabelROI(roi, tracksBarcodes: !barcodeBoxes.isEmpty, now: now)

            for finding in ranked {
                let key = finding.id
                let isNew = updated[key] == nil
                updated[key] = finding
                if isNew {
                    publishDebug("New barcode \(finding.symbology ?? "?"): \(finding.rawText.prefix(48))")
                    dispatchNewFinding(finding)
                }
            }

            for key in Array(updated.keys) {
                if seenKeys.contains(key) { continue }
                if updated[key]?.source == .ocr { continue }
                if updated[key]?.captureContext == .labelSnapshot { continue }
                if now.timeIntervalSince(updated[key]!.lastSeen) > missingThreshold {
                    updated.removeValue(forKey: key)
                }
            }

            tracking = updated
            publishVisible()
        } catch {
            publishDebug("Barcode Vision error: \(error.localizedDescription)")
        }
    }

    private func scheduleLabelSnapshotIfNeeded(
        image: CGImage?,
        reason: String,
        now: Date,
        bypassCooldown: Bool = false
    ) {
        guard let image else { return }
        if !bypassCooldown, now.timeIntervalSince(lastLabelSnapshotTime) < snapshotCooldown { return }
        guard !labelSnapshotInFlight else { return }
        guard let frameCopy = image.copy() else { return }

        labelSnapshotInFlight = true
        autoCapturePending = true
        lastLabelSnapshotTime = now
        let size = "\(frameCopy.width)×\(frameCopy.height)"
        publishLabelCaptureStatus("Saving frame…")
        publishDebug("Stream snapshot (\(reason)) @ \(size)")
        Task { @MainActor in
            isStreamSnapshotInFlight = true
        }

        let includeOCR = labelOCREnabled
        queue.async { [weak self] in
            let result = LabelSnapshotProcessor.analyze(frameCopy, includeOCR: includeOCR, now: now)
            self?.ingestLabelSnapshotFindings(
                result.findings,
                frameSize: size,
                image: frameCopy,
                triggerReason: reason,
                originalJPEG: nil,
                labelROI: result.labelROI
            )
            self?.labelSnapshotInFlight = false
            self?.noteAutoCaptureFinished()
        }
    }

    private func ingestLabelSnapshotFindings(
        _ findings: [ScanFinding],
        frameSize: String,
        image: CGImage,
        triggerReason: String,
        originalJPEG: Data?,
        labelROI: CGRect
    ) {
        let barcodeCount = findings.filter { $0.source == .barcode }.count
        let ocrCount = findings.filter { $0.source == .ocr }.count
        let isManual = triggerReason.lowercased().contains("manual")
        let isAuto = triggerReason.lowercased().contains("auto")
        let prefix = isManual ? "Manual scan" : (isAuto ? "Auto capture" : "Label capture")
        if findings.isEmpty {
            publishLabelCaptureStatus("Captured frame — no fields decoded")
        } else {
            publishLabelCaptureStatus("Captured — \(barcodeCount + ocrCount) field(s)")
        }

        Task { @MainActor [weak self] in
            self?.onStreamSnapshotSaved?(findings.count)
        }

        dispatchLabelSnapshotCaptured(
            image,
            findings: findings,
            reason: triggerReason,
            originalJPEG: originalJPEG,
            labelROI: labelROI
        )

        var updated = tracking
        for finding in findings {
            updated[finding.id] = finding
            dispatchNewFinding(finding)
        }
        tracking = updated
        publishVisible()
    }

    private func dispatchLabelSnapshotCaptured(
        _ image: CGImage,
        findings: [ScanFinding],
        reason: String,
        originalJPEG: Data?,
        labelROI: CGRect
    ) {
        Task { @MainActor [weak self] in
            self?.onLabelSnapshotCaptured?(image, findings, reason, originalJPEG, labelROI)
        }
    }

    private func publishLabelROI(_ roi: CGRect, tracksBarcodes: Bool, now: Date) {
        Task { @MainActor [weak self] in
            self?.activeLabelROI = roi
            self?.labelROITracksBarcodes = tracksBarcodes
        }
        evaluateAutoStreamCapture(tracksBarcodes: tracksBarcodes, now: now)
    }

    private func evaluateAutoStreamCapture(tracksBarcodes: Bool, now: Date) {
        tracksBarcodesInFrame = tracksBarcodes
        if tracksBarcodes, scannableCodeInFrame {
            if labelROIGreenSince == nil {
                labelROIGreenSince = now
            }
        } else {
            labelROIGreenSince = nil
        }

        guard !autoCapturePending else { return }
        guard now.timeIntervalSince(lastAutoCaptureTime) >= autoCaptureCooldown else { return }
        guard tracksBarcodes, scannableCodeInFrame,
              let greenSince = labelROIGreenSince,
              now.timeIntervalSince(greenSince) >= autoCaptureStableDuration else { return }

        scheduleLabelSnapshotIfNeeded(
            image: pendingSnapshotFrame,
            reason: "auto Scan (stream frame)",
            now: now
        )
    }

    private func ingestOCRFinding(_ finding: ScanFinding, at now: Date) {
        var updated = tracking
        let isNew = updated[finding.id] == nil
        updated[finding.id] = finding
        tracking = updated
        if isNew {
            dispatchNewFinding(finding)
        }
        publishVisible()
    }

    private func publishVisible() {
        let visible = tracking.values.sorted {
            $0.rawText.localizedCaseInsensitiveCompare($1.rawText) == .orderedAscending
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let changed = self.visibleFindings.map(\.id) != visible.map(\.id)
            self.visibleFindings = visible
            if changed {
                self.onVisibleSetChanged?(visible)
            }
        }
    }

    private func dispatchNewFinding(_ finding: ScanFinding) {
        Task { @MainActor [weak self] in
            self?.onNewFinding?(finding)
        }
    }

    private func publishDebug(_ message: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastDebugPublish) > 0.25
                || message.contains("New ")
                || message.contains("Label snapshot") else { return }
            self.lastDebugPublish = now
            self.lastScanDebugLine = message
            self.onScanDebug?(message)
        }
    }

    private func publishLabelCaptureStatus(_ message: String) {
        Task { @MainActor [weak self] in
            self?.labelCaptureStatus = message
            self?.onScanDebug?(message)
        }
    }

    private static let shippingSymbologies: [VNBarcodeSymbology] = {
        var list: [VNBarcodeSymbology] = [
            .qr, .code128, .pdf417, .aztec, .dataMatrix,
            .ean13, .ean8, .upce, .code39, .code93, .itf14,
        ]
        if #available(iOS 15.0, *) {
            list.append(.microQR)
        }
        if #available(iOS 17.0, *) {
            list.append(.gs1DataBar)
            list.append(.gs1DataBarLimited)
            list.append(.gs1DataBarExpanded)
        }
        return list
    }()
}
