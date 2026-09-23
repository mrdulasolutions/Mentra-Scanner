#!/usr/bin/env swift
import AppKit
import Foundation
import Vision

let paths = CommandLine.arguments.dropFirst()
guard !paths.isEmpty else {
    fputs("Usage: label_vision_probe.swift <image>...\n", stderr)
    exit(1)
}

let symbologies: [VNBarcodeSymbology] = [
    .qr, .code128, .pdf417, .aztec, .dataMatrix,
    .ean13, .ean8, .upce, .code39, .code93, .itf14,
]

for path in paths {
    let url = URL(fileURLWithPath: path)
    guard let image = NSImage(contentsOf: url),
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let cg = rep.cgImage else {
        print("\(path): failed to load")
        continue
    }

    let w = cg.width
    let h = cg.height
    let request = VNDetectBarcodesRequest()
    request.symbologies = symbologies
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    do {
        try handler.perform([request])
        let results = request.results ?? []
        print("\n=== \(url.lastPathComponent) \(w)x\(h) — \(results.count) barcodes ===")
        for obs in results {
            let payload = obs.payloadStringValue ?? "(empty)"
            print("  \(obs.symbology.rawValue): \(payload.prefix(120))")
        }

        let ocr = VNRecognizeTextRequest()
        ocr.recognitionLevel = .accurate
        try handler.perform([ocr])
        let lines = (ocr.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let joined = lines.prefix(8).joined(separator: " | ")
        print("  OCR preview: \(joined.prefix(200))")
    } catch {
        print("\(path): \(error)")
    }
}
