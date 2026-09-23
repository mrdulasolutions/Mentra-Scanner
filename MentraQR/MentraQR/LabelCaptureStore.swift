import CoreGraphics
import Foundation
import SQLite3
import UIKit

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor LabelCaptureStore {
    static let shared = LabelCaptureStore()

    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        openDatabase()
        createSchemaIfNeeded()
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    func saveCapture(
        image: CGImage,
        findings: [ScanFinding],
        triggerReason: String,
        originalJPEG: Data? = nil,
        labelROI: CGRect? = nil,
        createdAt: Date = Date()
    ) throws -> LabelCaptureRecord {
        let id = UUID()
        let fileName = "\(id.uuidString).jpg"
        let imageURL = LabelCapturePaths.imagesDirectory.appendingPathComponent(fileName)
        guard let prepared = CaptureImageProcessor.prepareForStorage(cgImage: image, originalJPEG: originalJPEG) else {
            throw LabelCaptureStoreError.imageEncodingFailed
        }
        try prepared.jpegData.write(to: imageURL, options: .atomic)

        let stored = findings.map(StoredScanFinding.init(from:))
        let findingsJSON = try encoder.encode(stored)
        let findingsString = String(data: findingsJSON, encoding: .utf8) ?? "[]"
        let storedROI = labelROI.map(StoredLabelROI.init)
        let roiJSON = storedROI.flatMap { try? encoder.encode($0) }
        let roiString = roiJSON.flatMap { String(data: $0, encoding: .utf8) }

        let record = LabelCaptureRecord(
            id: id,
            createdAt: createdAt,
            triggerReason: triggerReason,
            frameWidth: prepared.width,
            frameHeight: prepared.height,
            imageFileName: fileName,
            findings: stored,
            labelROI: storedROI
        )

        try insert(record: record, findingsJSON: findingsString, labelROIJSON: roiString)
        return record
    }

    func fetchAll(limit: Int = 200) throws -> [LabelCaptureRecord] {
        guard let db else { throw LabelCaptureStoreError.databaseUnavailable }
        let sql = """
        SELECT id, created_at, trigger_reason, frame_width, frame_height, image_path, findings_json, label_roi_json
        FROM label_captures
        ORDER BY created_at DESC
        LIMIT ?;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw LabelCaptureStoreError.queryFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(limit))

        var rows: [LabelCaptureRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let record = try? rowToRecord(statement) {
                rows.append(record)
            }
        }
        return rows
    }

    func delete(id: UUID) throws {
        guard let db else { throw LabelCaptureStoreError.databaseUnavailable }
        if let record = try fetchOne(id: id) {
            let imageURL = LabelCapturePaths.imagesDirectory.appendingPathComponent(record.imageFileName)
            try? FileManager.default.removeItem(at: imageURL)
        }
        let sql = "DELETE FROM label_captures WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw LabelCaptureStoreError.queryFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LabelCaptureStoreError.queryFailed(lastErrorMessage)
        }
    }

    func deleteAll() throws {
        let all = try fetchAll(limit: 10_000)
        for record in all {
            try delete(id: record.id)
        }
    }

    private func fetchOne(id: UUID) throws -> LabelCaptureRecord? {
        guard let db else { throw LabelCaptureStoreError.databaseUnavailable }
        let sql = """
        SELECT id, created_at, trigger_reason, frame_width, frame_height, image_path, findings_json, label_roi_json
        FROM label_captures WHERE id = ? LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw LabelCaptureStoreError.queryFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try rowToRecord(statement)
    }

    private func openDatabase() {
        let path = LabelCapturePaths.databaseURL.path
        if sqlite3_open(path, &db) != SQLITE_OK {
            db = nil
        }
    }

    private func createSchemaIfNeeded() {
        guard let db else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS label_captures (
            id TEXT PRIMARY KEY NOT NULL,
            created_at REAL NOT NULL,
            trigger_reason TEXT NOT NULL,
            frame_width INTEGER NOT NULL,
            frame_height INTEGER NOT NULL,
            image_path TEXT NOT NULL,
            findings_json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_label_captures_created_at ON label_captures(created_at DESC);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
        sqlite3_exec(
            db,
            "ALTER TABLE label_captures ADD COLUMN label_roi_json TEXT;",
            nil,
            nil,
            nil
        )
    }

    private func insert(record: LabelCaptureRecord, findingsJSON: String, labelROIJSON: String?) throws {
        guard let db else { throw LabelCaptureStoreError.databaseUnavailable }
        let sql = """
        INSERT INTO label_captures
        (id, created_at, trigger_reason, frame_width, frame_height, image_path, findings_json, label_roi_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw LabelCaptureStoreError.queryFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, record.id.uuidString, -1, sqliteTransient)
        sqlite3_bind_double(statement, 2, record.createdAt.timeIntervalSince1970)
        sqlite3_bind_text(statement, 3, record.triggerReason, -1, sqliteTransient)
        sqlite3_bind_int(statement, 4, Int32(record.frameWidth))
        sqlite3_bind_int(statement, 5, Int32(record.frameHeight))
        sqlite3_bind_text(statement, 6, record.imageFileName, -1, sqliteTransient)
        sqlite3_bind_text(statement, 7, findingsJSON, -1, sqliteTransient)
        if let labelROIJSON {
            sqlite3_bind_text(statement, 8, labelROIJSON, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, 8)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LabelCaptureStoreError.queryFailed(lastErrorMessage)
        }
    }

    private func rowToRecord(_ statement: OpaquePointer?) throws -> LabelCaptureRecord {
        guard let statement else { throw LabelCaptureStoreError.queryFailed("missing row") }
        let idString = String(cString: sqlite3_column_text(statement, 0))
        guard let id = UUID(uuidString: idString) else {
            throw LabelCaptureStoreError.corruptRow
        }
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        let trigger = String(cString: sqlite3_column_text(statement, 2))
        let width = Int(sqlite3_column_int(statement, 3))
        let height = Int(sqlite3_column_int(statement, 4))
        let imagePath = String(cString: sqlite3_column_text(statement, 5))
        let jsonCString = sqlite3_column_text(statement, 6)
        let jsonString = jsonCString.map { String(cString: $0) } ?? "[]"
        let findingsData = Data(jsonString.utf8)
        let findings = (try? decoder.decode([StoredScanFinding].self, from: findingsData)) ?? []

        var labelROI: StoredLabelROI?
        if sqlite3_column_count(statement) > 7 {
            if let roiCString = sqlite3_column_text(statement, 7) {
                let roiString = String(cString: roiCString)
                if let data = roiString.data(using: .utf8) {
                    labelROI = try? decoder.decode(StoredLabelROI.self, from: data)
                }
            }
        }

        return LabelCaptureRecord(
            id: id,
            createdAt: createdAt,
            triggerReason: trigger,
            frameWidth: width,
            frameHeight: height,
            imageFileName: imagePath,
            findings: findings,
            labelROI: labelROI
        )
    }

    private var lastErrorMessage: String {
        guard let db, let message = sqlite3_errmsg(db) else { return "unknown SQLite error" }
        return String(cString: message)
    }
}

enum LabelCaptureStoreError: LocalizedError {
    case databaseUnavailable
    case imageEncodingFailed
    case queryFailed(String)
    case corruptRow

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "Capture database is not available."
        case .imageEncodingFailed:
            return "Could not encode label image."
        case .queryFailed(let detail):
            return "Database error: \(detail)"
        case .corruptRow:
            return "Corrupt capture record."
        }
    }
}
