import SwiftUI

struct CapturesView: View {
    @EnvironmentObject private var captureLibrary: LabelCaptureLibrary

    var body: some View {
        NavigationStack {
            Group {
                if captureLibrary.records.isEmpty {
                    MentraEmptyState(
                        symbol: "tray.full",
                        title: "No captures",
                        message: "Stream frames and parsed fields from your scans are saved here automatically."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppDesign.groupedBackground)
                } else {
                    List {
                        ForEach(captureLibrary.records) { record in
                            NavigationLink {
                                CaptureDetailView(record: record)
                            } label: {
                                CaptureRow(record: record)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Captures")
            .navigationBarTitleDisplayMode(.large)
            .background(AppDesign.groupedBackground)
            .toolbar {
                if !captureLibrary.records.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear all", role: .destructive) {
                            captureLibrary.deleteAll()
                        }
                    }
                }
            }
            .refreshable {
                await captureLibrary.reload()
            }
            .task {
                await captureLibrary.reload()
            }
            .safeAreaInset(edge: .bottom) {
                if let error = captureLibrary.lastSaveError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let record = captureLibrary.records[index]
            captureLibrary.delete(record)
        }
    }
}

private struct CaptureRow: View {
    let record: LabelCaptureRecord

    var body: some View {
        HStack(spacing: 12) {
            CaptureThumbnail(fileName: record.imageFileName)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(record.summaryLine)
                    .font(.headline)
                    .lineLimit(1)
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.triggerReason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CaptureThumbnail: View {
    let fileName: String

    var body: some View {
        let url = LabelCapturePaths.imagesDirectory.appendingPathComponent(fileName)
        if let uiImage = CaptureImageProcessor.imageForDisplay(fileURL: url) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else {
            Color.secondary.opacity(0.2)
        }
    }
}

private struct StoredFindingRow: View {
    let finding: StoredScanFinding

    private var presentation: ScanFieldPresentation { finding.fieldPresentation }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(presentation.title)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(chipColor.opacity(0.18))
                    .clipShape(Capsule())
                if let detail = presentation.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let tracking = finding.trackingId {
                Text(tracking)
                    .font(.body.monospaced())
            }
            Text(finding.rawText)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(presentation.kind == .labelExcerpt ? 12 : 6)
            Button("Copy text") {
                UIPasteboard.general.string = finding.rawText
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        Divider()
    }

    private var chipColor: Color {
        switch presentation.section {
        case .shipping: .orange
        case .qrAndLinks: .purple
        case .barcodes: .blue
        case .labelText: .teal
        case .other: .gray
        }
    }
}

struct CaptureDetailView: View {
    let record: LabelCaptureRecord
    @EnvironmentObject private var captureLibrary: LabelCaptureLibrary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let uiImage = CaptureImageProcessor.imageForDisplay(fileURL: record.imageFileURL) {
                    ZStack {
                        ZoomableImageView(image: uiImage, contentKey: record.id.uuidString)
                        CaptureLabelROIOverlay(
                            normalizedROI: record.labelROI?.rect ?? LabelScanROI.defaultGuide,
                            imageSize: uiImage.size
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(uiImage.size.width / max(uiImage.size.height, 1), contentMode: .fit)
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("Pinch to zoom · cyan box = OCR parse region · \(Int(uiImage.size.width))×\(Int(uiImage.size.height)) px")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Captured", value: record.createdAt.formatted(date: .complete, time: .standard))
                LabeledContent("Trigger", value: record.triggerReason)
                LabeledContent("Frame", value: "\(record.frameWidth)×\(record.frameHeight)")

                if record.findings.isEmpty {
                    Text("No parsed QR/OCR fields on this snapshot.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Parsed data (\(record.findings.count))")
                        .font(.headline)
                    ForEach(FindingLabelTaxonomy.groupedStoredFindings(record.findings), id: \.section) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.section.rawValue)
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            ForEach(group.items) { finding in
                                StoredFindingRow(finding: finding)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Label capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    captureLibrary.delete(record)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }
}
