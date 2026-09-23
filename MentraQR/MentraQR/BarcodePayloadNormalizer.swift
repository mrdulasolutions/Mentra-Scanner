import Foundation

enum BarcodePayloadNormalizer {
    /// Cleans Vision payloads (GS1 separators, control chars) for carrier parsers.
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.uppercased().contains("1Z") {
            let alnum = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
            if alnum.hasPrefix("1Z"), alnum.count >= 16 {
                return alnum
            }
        }

        let segments = trimmed.split(whereSeparator: { char in
            guard let scalar = char.unicodeScalars.first?.value else { return true }
            return scalar < 32 || scalar == 127
        }).map(String.init)

        if segments.count > 1 {
            for segment in segments.reversed() {
                let digits = segment.filter(\.isNumber)
                if digits.hasPrefix("9405") || (digits.hasPrefix("92") && digits.count >= 20) {
                    return digits
                }
                if digits.hasPrefix("94") && digits.count >= 20 {
                    return digits
                }
                if digits.count >= 30 {
                    return digits
                }
            }
        }

        let digitsOnly = trimmed.filter(\.isNumber)
        if digitsOnly.count >= 10 {
            return digitsOnly
        }

        return trimmed
    }
}
