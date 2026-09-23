import CoreGraphics
import Foundation

@MainActor
final class LabelCaptureLibrary: ObservableObject {
    @Published private(set) var records: [LabelCaptureRecord] = []
    @Published private(set) var lastSaveError: String?
    @Published private(set) var lastSavedRecordID: UUID?

    private let store = LabelCaptureStore.shared

    func reload() async {
        do {
            records = try await store.fetchAll()
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    func persistLabelSnapshot(
        image: CGImage,
        findings: [ScanFinding],
        triggerReason: String,
        originalJPEG: Data? = nil,
        labelROI: CGRect? = nil
    ) {
        Task {
            do {
                let record = try await store.saveCapture(
                    image: image,
                    findings: findings,
                    triggerReason: triggerReason,
                    originalJPEG: originalJPEG,
                    labelROI: labelROI
                )
                records.insert(record, at: 0)
                if records.count > 200 {
                    records = Array(records.prefix(200))
                }
                lastSavedRecordID = record.id
                lastSaveError = nil
            } catch {
                lastSaveError = error.localizedDescription
            }
        }
    }

    func delete(_ record: LabelCaptureRecord) {
        Task {
            do {
                try await store.delete(id: record.id)
                records.removeAll { $0.id == record.id }
            } catch {
                lastSaveError = error.localizedDescription
            }
        }
    }

    func deleteAll() {
        Task {
            do {
                try await store.deleteAll()
                records = []
            } catch {
                lastSaveError = error.localizedDescription
            }
        }
    }
}
