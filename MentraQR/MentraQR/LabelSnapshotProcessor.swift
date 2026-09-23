import CoreGraphics
import Foundation
import Vision

/// One-shot hi-res label pass: QR on frame; OCR inside inferred label ROI.
enum LabelSnapshotProcessor {
    private static let snapshotMinLongEdge: CGFloat = 2800

    struct AnalysisResult {
        let findings: [ScanFinding]
        let labelROI: CGRect
    }

    static func analyze(_ image: CGImage, now: Date = Date()) -> AnalysisResult {
        let scaled = VisionFrameScaler.scaledForBarcodeScan(image, minLongEdge: snapshotMinLongEdge)
        var barcodeBoxes: [CGRect] = []
        let qrFindings = detectLabelQRCodes(in: scaled, now: now, boxesOut: &barcodeBoxes)
        let labelROI = LabelScanROI.inferred(from: barcodeBoxes)
        let ocrFindings = LabelTextRecognizer.snapshotFindings(on: scaled, labelROI: labelROI, now: now)
        return AnalysisResult(
            findings: qrFindings + ocrFindings,
            labelROI: labelROI
        )
    }

    private static func detectLabelQRCodes(
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

    private static let qrSymbologies: [VNBarcodeSymbology] = {
        var list: [VNBarcodeSymbology] = [.qr]
        if #available(iOS 15.0, *) {
            list.append(.microQR)
        }
        return list
    }()
}
