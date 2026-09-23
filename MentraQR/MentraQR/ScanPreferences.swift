import Foundation

/// Operator toggles persisted across launches.
enum ScanPreferences {
    private static let labelOCRKey = "mentraqr.scan.labelOCREnabled"

    /// Printed label text via Vision OCR (live stream + captures). Default off for QR-only workflows.
    static var labelOCREnabled: Bool {
        get { UserDefaults.standard.bool(forKey: labelOCRKey) }
        set { UserDefaults.standard.set(newValue, forKey: labelOCRKey) }
    }
}
