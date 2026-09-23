#!/usr/bin/env swift
// Smoke-test parser strings from Vision probe on sample labels (run from repo).
import Foundation

// Mirror of production logic — keep in sync with ShippingBarcodeParser + BarcodePayloadNormalizer.

func normalize(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.uppercased().contains("1Z") {
        let alnum = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        if alnum.hasPrefix("1Z") { return alnum }
    }
    let segments = trimmed.split(whereSeparator: { ($0.unicodeScalars.first?.value ?? 0) < 32 }).map(String.init)
    for segment in segments.reversed() {
        let digits = segment.filter(\.isNumber)
        if digits.hasPrefix("9405"), digits.count >= 20 { return digits }
        if digits.count >= 30 { return digits }
    }
    let digits = trimmed.filter(\.isNumber)
    return digits.count >= 10 ? digits : trimmed
}

func parseFedExDigits(_ digits: String) -> String? {
    if digits.count == 34, digits.hasPrefix("96") { return String(digits.suffix(12)) }
    if digits.count == 12 { return digits }
    return nil
}

func parseUSPS(_ digits: String) -> String? {
    if let r = digits.range(of: "9405") {
        let tail = String(digits[r.lowerBound...])
        if tail.count >= 20 { return String(tail.prefix(22)) }
    }
    return nil
}

struct Case { let raw: String; let carrier: String; let tracking: String }
let cases: [Case] = [
    Case(raw: "9622001900009621727000272483686596", carrier: "FedEx", tracking: "272483686596"),
    Case(raw: "1Z29F6163627360833", carrier: "UPS", tracking: "1Z29F6163627360833"),
    Case(raw: "42060199\u{1d}9405511899560754442163", carrier: "USPS", tracking: "9405511899560754442163"),
]

var failed = 0
for c in cases {
    let norm = normalize(c.raw)
    var ok = false
    if c.carrier == "FedEx" { ok = parseFedExDigits(norm) == c.tracking }
    if c.carrier == "UPS" { ok = norm == c.tracking }
    if c.carrier == "USPS" { ok = parseUSPS(norm) == c.tracking }
    print("\(ok ? "OK" : "FAIL") \(c.carrier) norm=\(norm.prefix(40)) expected=\(c.tracking)")
    if !ok { failed += 1 }
}
exit(failed == 0 ? 0 : 1)
