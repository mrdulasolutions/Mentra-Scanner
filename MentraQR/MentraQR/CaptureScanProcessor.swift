import CoreGraphics
import Foundation
import Vision

/// Full parcel decode on a frozen capture (barcodes full-frame; OCR inside label ROI).
enum CaptureScanProcessor {
    private static let captureMinLongEdge: CGFloat = 3200

    struct AnalysisResult {
        let findings: [ScanFinding]
        let labelROI: CGRect
    }

    static func analyze(_ image: CGImage, now: Date = Date()) -> AnalysisResult {
        let scaled = VisionFrameScaler.scaledForBarcodeScan(image, minLongEdge: captureMinLongEdge)
        var findings: [ScanFinding] = []
        var barcodeBoxes: [CGRect] = []

        findings.append(contentsOf: detectShippingBarcodes(in: image, now: now, boxesOut: &barcodeBoxes))
        findings.append(contentsOf: detectShippingBarcodes(in: scaled, now: now, boxesOut: &barcodeBoxes))
        findings.append(contentsOf: detectQRCodes(in: image, now: now, boxesOut: &barcodeBoxes))
        findings.append(contentsOf: detectQRCodes(in: scaled, now: now, boxesOut: &barcodeBoxes))

        let labelROI = LabelScanROI.inferred(from: barcodeBoxes)
        findings.append(contentsOf: LabelTextRecognizer.snapshotFindings(on: scaled, labelROI: labelROI, now: now))

        return AnalysisResult(findings: dedupeById(findings), labelROI: labelROI)
    }

    private static func detectQRCodes(
        in image: CGImage,
        now: Date,
        boxesOut: inout [CGRect]
    ) -> [ScanFinding] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = qrSymbologies
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        var out: [ScanFinding] = []
        for observation in request.results ?? [] {
            guard let raw = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { continue }
            let symName = observation.symbology.rawValue
            guard symName.lowercased().contains("qr") else { continue }

            boxesOut.append(observation.boundingBox)
            let normalized = BarcodePayloadNormalizer.normalize(raw)
            let displayText = normalized.isEmpty ? raw : normalized
            let parsed = ShippingBarcodeParser.parse(text: raw, symbology: symName)
                ?? ShippingBarcodeParser.parseQRCodePayload(displayText)
            let key = ParcelKey.snapshotQRKey(displayText)
            out.append(
                ScanFinding(
                    id: key,
                    source: .barcode,
                    symbology: symName,
                    rawText: displayText,
                    boundingBox: observation.boundingBox,
                    lastSeen: now,
                    parsed: parsed,
                    captureContext: .labelSnapshot
                )
            )
        }
        return out
    }

    private static func detectShippingBarcodes(
        in image: CGImage,
        now: Date,
        boxesOut: inout [CGRect]
    ) -> [ScanFinding] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = shippingSymbologies
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        var out: [ScanFinding] = []
        for observation in request.results ?? [] {
            guard let raw = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { continue }
            let symName = observation.symbology.rawValue
            if symName.lowercased().contains("qr") { continue }

            boxesOut.append(observation.boundingBox)
            let normalized = BarcodePayloadNormalizer.normalize(raw)
            let parsed = ShippingBarcodeParser.parse(text: raw, symbology: symName)
            let displayText = normalized.isEmpty ? raw : normalized
            let key = parsed?.parcelKey.map { "parcel:\($0)" }
                ?? ParcelKey.barcodeTrackingKey(symbology: symName, raw: displayText)
            out.append(
                ScanFinding(
                    id: "snap-\(key)",
                    source: .barcode,
                    symbology: symName,
                    rawText: displayText,
                    boundingBox: observation.boundingBox,
                    lastSeen: now,
                    parsed: parsed,
                    captureContext: .labelSnapshot
                )
            )
        }
        return out.sorted {
            ShippingBarcodeParser.rankingScore(for: $0) > ShippingBarcodeParser.rankingScore(for: $1)
        }
    }

    private static func dedupeById(_ findings: [ScanFinding]) -> [ScanFinding] {
        var seen = Set<String>()
        var out: [ScanFinding] = []
        for finding in findings {
            guard !seen.contains(finding.id) else { continue }
            seen.insert(finding.id)
            out.append(finding)
        }
        return out
    }

    private static let qrSymbologies: [VNBarcodeSymbology] = {
        var list: [VNBarcodeSymbology] = [.qr]
        if #available(iOS 15.0, *) {
            list.append(.microQR)
        }
        return list
    }()

    private static let shippingSymbologies: [VNBarcodeSymbology] = {
        var list: [VNBarcodeSymbology] = [
            .code128, .pdf417, .aztec, .dataMatrix,
            .ean13, .ean8, .upce, .code39, .code93, .itf14,
        ]
        if #available(iOS 17.0, *) {
            list.append(.gs1DataBar)
            list.append(.gs1DataBarLimited)
            list.append(.gs1DataBarExpanded)
        }
        return list
    }()
}
