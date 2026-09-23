import Foundation

/// Shapes decoded QR text for Laya / Core ML token limits (front-load host and risk cues).
enum PayloadURLShaping {
    static func forLaya(_ payload: String) -> String {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            if trimmed.count > 400 {
                return String(trimmed.prefix(400))
            }
            return trimmed
        }

        var parts: [String] = []
        if let host = url.host?.lowercased(), !host.isEmpty {
            parts.append(host)
        }
        let path = url.path
        if !path.isEmpty, path != "/" {
            let pathCap = path.count > 120 ? String(path.prefix(120)) : path
            parts.append(pathCap)
        }
        if let query = url.query, !query.isEmpty {
            let keys = query.split(separator: "&").prefix(8).map { pair -> String in
                String(pair.split(separator: "=", maxSplits: 1).first ?? Substring(pair))
            }
            if !keys.isEmpty {
                parts.append("?" + keys.joined(separator: "&"))
            }
        }
        let shaped = parts.joined(separator: " ")
        if shaped.isEmpty { return trimmed.prefix(200).description }
        return shaped.count > 400 ? String(shaped.prefix(400)) : shaped
    }
}
