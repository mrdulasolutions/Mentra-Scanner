import Foundation

/// Per-capture phase timestamps for diagnostics and on-device tuning.
struct CapturePhaseMetrics {
    let tTrigger = Date()
    var tStopAck: Date?
    var tPhotoAck: Date?
    var tJpeg: Date?
    var tResumeAck: Date?
    var tOcrDone: Date?

    func summary() -> String {
        func ms(_ from: Date?, _ to: Date?) -> String {
            guard let from, let to else { return "—" }
            return String(format: "%.0fms", to.timeIntervalSince(from) * 1000)
        }
        let stopMs = ms(tTrigger, tStopAck)
        let photoMs = ms(tStopAck ?? tTrigger, tPhotoAck)
        let jpegMs = ms(tPhotoAck ?? tStopAck ?? tTrigger, tJpeg)
        let resumeMs = ms(tJpeg ?? tPhotoAck, tResumeAck)
        let ocrMs = ms(tResumeAck ?? tJpeg, tOcrDone)
        return "stop=\(stopMs) photo=\(photoMs) jpeg=\(jpegMs) resume=\(resumeMs) ocr=\(ocrMs)"
    }
}
