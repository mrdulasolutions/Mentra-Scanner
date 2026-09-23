import CoreGraphics
import Foundation
import Vision

/// Throttled OCR on stream frames for printed shipping label text.
final class LabelTextRecognizer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.local.mentraqr.ocr", qos: .userInitiated)
    private var lastProcessTime = Date.distantPast
    private let minInterval: TimeInterval = 0.35
    private var candidateExcerpt = ""
    private var candidateSince = Date.distantPast
    private var lastEmittedBlockKey = ""
    private let stabilizeDuration: TimeInterval = 0.75
    private var lineFirstSeen: [String: Date] = [:]
    private var emittedLineKeys = Set<String>()
    private let lineStabilizeDuration: TimeInterval = 0.5

    var onDebug: ((String) -> Void)?
    /// Fired when a frame looks like a dense shipping label (for hi-res capture).
    var onDenseLabelFrame: ((Int) -> Void)?

    func reset() {
        queue.sync {
            candidateExcerpt = ""
            candidateSince = Date.distantPast
            lastEmittedBlockKey = ""
            lastProcessTime = Date.distantPast
            lineFirstSeen.removeAll()
            emittedLineKeys.removeAll()
        }
    }

    func process(_ image: CGImage, labelROI: CGRect, now: Date = Date()) -> [ScanFinding] {
        guard now.timeIntervalSince(lastProcessTime) >= minInterval else { return [] }
        lastProcessTime = now
        let scaled = VisionFrameScaler.scaledForBarcodeScan(image, minLongEdge: 2000)
        let cropped = LabelScanROI.crop(scaled, normalized: labelROI) ?? scaled
        return queue.sync {
            recognizeAndEmit(cropped, now: now)
        }
    }

    private func recognizeAndEmit(_ image: CGImage, now: Date) -> [ScanFinding] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.006
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            onDebug?("OCR perform failed: \(error.localizedDescription)")
            return []
        }

        let observations = request.results ?? []
        let lines = linesInReadingOrder(from: observations)
        if lines.isEmpty {
            return []
        }

        onDebug?("OCR saw \(lines.count) lines in frame")
        if lines.count >= 3 {
            onDenseLabelFrame?(lines.count)
        }

        var findings: [ScanFinding] = []
        findings.append(contentsOf: emitStableLines(lines, now: now))
        if let block = emitStableBlock(from: lines, now: now) {
            findings.append(block)
        }
        return findings
    }

    private func linesInReadingOrder(from observations: [VNRecognizedTextObservation]) -> [String] {
        observations
            .sorted { lhs, rhs in
                let ly = lhs.boundingBox.midY
                let ry = rhs.boundingBox.midY
                if abs(ly - ry) > 0.02 { return ly > ry }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func emitStableLines(_ lines: [String], now: Date) -> [ScanFinding] {
        var out: [ScanFinding] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3 else { continue }
            let lineKey = ParcelKey.ocrLineKey(trimmed)
            if emittedLineKeys.contains(lineKey) { continue }

            if lineFirstSeen[lineKey] == nil {
                lineFirstSeen[lineKey] = now
                continue
            }
            guard now.timeIntervalSince(lineFirstSeen[lineKey]!) >= lineStabilizeDuration else {
                continue
            }

            emittedLineKeys.insert(lineKey)
            let parsed = ShippingBarcodeParser.parseOCRText(trimmed)
            onDebug?("OCR line: \(trimmed.prefix(40))")
            out.append(
                ScanFinding(
                    id: lineKey,
                    source: .ocr,
                    symbology: "label_line",
                    rawText: trimmed,
                    boundingBox: nil,
                    lastSeen: now,
                    parsed: parsed
                )
            )
        }
        return out
    }

    private func emitStableBlock(from lines: [String], now: Date) -> ScanFinding? {
        let excerpt = buildExcerpt(from: lines)
        guard excerpt.count >= 6 else { return nil }

        if excerpt != candidateExcerpt {
            candidateExcerpt = excerpt
            candidateSince = now
            return nil
        }
        guard now.timeIntervalSince(candidateSince) >= stabilizeDuration else {
            return nil
        }

        let parsed = ShippingBarcodeParser.parseOCRText(excerpt)
        let key = parsed?.parcelKey.map { "parcel:\($0)" } ?? ParcelKey.ocrExcerptKey(excerpt)
        guard key != lastEmittedBlockKey else { return nil }
        lastEmittedBlockKey = key

        onDebug?("OCR block \(lines.count) lines → \(parsed?.carrier ?? "text")")

        return ScanFinding(
            id: key,
            source: .ocr,
            symbology: "label_text",
            rawText: excerpt,
            boundingBox: nil,
            lastSeen: now,
            parsed: parsed
        )
    }

    private func buildExcerpt(from lines: [String]) -> String {
        let unique = dedupeLinesPreservingOrder(lines)
        let joined = unique.prefix(24).joined(separator: "\n")
        if joined.count <= 600 { return joined }
        return String(joined.prefix(600))
    }

    private func dedupeLinesPreservingOrder(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in lines {
            let norm = line.uppercased().filter { !$0.isWhitespace }
            guard norm.count >= 2 else { continue }
            if seen.contains(norm) { continue }
            seen.insert(norm)
            out.append(line)
        }
        return out
    }

    /// Full OCR on a frozen label frame (no throttling or stabilization).
    static func snapshotFindings(on image: CGImage, labelROI: CGRect, now: Date = Date()) -> [ScanFinding] {
        let cropped = LabelScanROI.crop(image, normalized: labelROI) ?? image
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.004
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: cropped, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        let observations = request.results ?? []
        let lines = observations
            .sorted { lhs, rhs in
                let ly = lhs.boundingBox.midY
                let ry = rhs.boundingBox.midY
                if abs(ly - ry) > 0.02 { return ly > ry }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [] }

        var findings: [ScanFinding] = []
        var seenLineKeys = Set<String>()
        for line in lines {
            guard line.count >= 2 else { continue }
            let key = ParcelKey.snapshotOcrLineKey(line)
            guard !seenLineKeys.contains(key) else { continue }
            seenLineKeys.insert(key)
            let parsed = ShippingBarcodeParser.parseOCRText(line)
            findings.append(
                ScanFinding(
                    id: key,
                    source: .ocr,
                    symbology: "label_line",
                    rawText: line,
                    boundingBox: nil,
                    lastSeen: now,
                    parsed: parsed,
                    captureContext: .labelSnapshot
                )
            )
        }

        let unique = dedupeLinesStatic(lines)
        let block = unique.prefix(32).joined(separator: "\n")
        if block.count >= 6 {
            let parsed = ShippingBarcodeParser.parseOCRText(block)
            let blockKey = parsed?.parcelKey.map { "parcel:\($0)" } ?? ParcelKey.snapshotOcrBlockKey(block)
            findings.append(
                ScanFinding(
                    id: blockKey,
                    source: .ocr,
                    symbology: "label_text",
                    rawText: block,
                    boundingBox: nil,
                    lastSeen: now,
                    parsed: parsed,
                    captureContext: .labelSnapshot
                )
            )
        }
        return findings
    }

    private static func dedupeLinesStatic(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in lines {
            let norm = line.uppercased().filter { !$0.isWhitespace }
            guard norm.count >= 2 else { continue }
            if seen.contains(norm) { continue }
            seen.insert(norm)
            out.append(line)
        }
        return out
    }
}
