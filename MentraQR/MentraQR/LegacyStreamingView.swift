import SwiftUI

/// WHIP live preview + frame-by-frame decode (developer path).
struct LegacyStreamingView: View {
    @EnvironmentObject private var session: MentraSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Manual WHIP controls. Everyday scanning uses Start / Stop on the Scan tab.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(session.isQRScanActive ? "Stop stream" : "Start stream") {
                        session.toggleQRScanning()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.isConnected || session.isScanInProgress)

                    if session.isQRScanActive, !session.previewHasVideo {
                        ProgressView()
                    }
                }

                streamPreviewPanel

                if !session.frameScanDecoder.visibleFindings.isEmpty {
                    Text("In stream (\(session.frameScanDecoder.visibleFindings.count))")
                        .font(.headline)
                    ForEach(session.frameScanDecoder.visibleFindings) { finding in
                        ScanResultRow(
                            finding: finding,
                            decision: session.payloadDecisions[finding.id]
                        )
                    }
                }

                streamStatusBlock
            }
            .padding()
        }
        .navigationTitle("Live stream (WHIP)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var streamPreviewPanel: some View {
        ZStack {
            StreamPreviewView(
                receiver: session.whipReceiver,
                detections: session.frameScanDecoder.visibleFindings
            )
            .frame(minHeight: 220)
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if session.isConnected, session.isQRScanActive {
                LabelGuideOverlay(
                    normalizedROI: session.frameScanDecoder.activeLabelROI,
                    tracksContent: session.frameScanDecoder.labelROITracksBarcodes
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !session.previewHasVideo {
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(streamPlaceholder)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(session.previewHasVideo ? Color.green : Color.gray.opacity(0.5), lineWidth: 2)
        )
    }

    private var streamPlaceholder: String {
        if !session.isConnected { return "Connect glasses on the Connect tab." }
        if !session.isQRScanActive { return "Tap Start stream." }
        if session.activeWhipURL.isEmpty { return "Starting receiver…" }
        return "Waiting for video from glasses."
    }

    private var streamStatusBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.streamStatus)
                .font(.footnote)
            if !session.activeWhipURL.isEmpty {
                Text(session.activeWhipURL)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
