import SwiftUI

struct ScannerView: View {
    @EnvironmentObject private var session: MentraSession

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppDesign.sectionSpacing) {
                    MentraConnectionStrip(
                        isConnected: session.isConnected,
                        isLive: session.isQRScanActive && session.previewHasVideo,
                        glassesWifiSummary: session.glassesWifiText,
                        actionHint: connectionHint
                    )

                    livePreviewPanel

                    if let toast = session.captureToast {
                        Label(toast, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if session.isScanInProgress {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Saving frame…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !session.manualScanStatus.isEmpty, session.captureToast == nil {
                        Text(session.manualScanStatus)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if session.lastScanPreviewImage == nil, session.isConnected, session.glassesWifiConnected {
                        if session.isQRScanActive {
                            MentraEmptyState(
                                symbol: "viewfinder",
                                title: "Ready to scan",
                                message: "Point at a QR or barcode in the guide box. Captures save automatically while live scan is on."
                            )
                            .mentraCard()
                        } else {
                            MentraEmptyState(
                                symbol: "play.circle",
                                title: "Live scan is off",
                                message: "Tap Start live below when you are ready to scan."
                            )
                            .mentraCard()
                        }
                    }

                    lastCapturePanel
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .animation(.easeInOut(duration: 0.25), value: session.captureToast)
            .background(AppDesign.groupedBackground)
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                scanActionsBar
                    .background(.bar)
            }
            .onAppear {
                session.refreshPhoneNetwork()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        session.toggleGlassesFillLight()
                    } label: {
                        Image(systemName: session.glassesFillLightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .foregroundStyle(session.glassesFillLightOn ? .yellow : .primary)
                    }
                    .disabled(!session.isConnected)
                    .accessibilityLabel(session.glassesFillLightOn ? "Fill light on" : "Fill light off")
                }
            }
        }
    }

    private var connectionHint: String? {
        if !session.isConnected {
            return "Open Connect to pair your glasses."
        }
        if !session.glassesWifiConnected {
            return "In Settings, set up Wi‑Fi so glasses and iPhone share a network."
        }
        return nil
    }

    private var livePreviewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            MentraSectionHeader(
                title: "Live view",
                subtitle: liveSubtitle
            )

            ZStack {
                StreamPreviewView(
                    receiver: session.whipReceiver,
                    detections: session.frameScanDecoder.visibleFindings
                )
                .frame(minHeight: 220)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(Color.black)

                if session.isConnected, session.isQRScanActive {
                    LabelGuideOverlay(
                        normalizedROI: session.frameScanDecoder.activeLabelROI,
                        tracksContent: session.frameScanDecoder.labelROITracksBarcodes
                    )
                }

                if !session.previewHasVideo {
                    VStack(spacing: 10) {
                        if session.isQRScanActive {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(livePlaceholder)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.62))
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous)
                    .strokeBorder(
                        session.previewHasVideo ? Color.green.opacity(0.7) : Color.primary.opacity(0.12),
                        lineWidth: session.previewHasVideo ? 2 : 1
                    )
            }
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        }
    }

    private var liveSubtitle: String {
        if session.isQRScanActive {
            return "QR or barcode in the guide auto-saves a frame"
        }
        return "Start live scan to begin"
    }

    private var livePlaceholder: String {
        if !session.isConnected { return "Connect your glasses to begin." }
        if !session.glassesWifiConnected { return "Set up Wi‑Fi in Settings." }
        if !session.isQRScanActive { return "Tap Start live below." }
        return "Waiting for video from glasses…"
    }

    private var lastCapturePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            MentraSectionHeader(title: "Last capture", subtitle: "Most recent saved frame")

            Group {
                if let image = session.lastScanPreviewImage {
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                            if let roi = session.lastScanLabelROI {
                                CaptureLabelROIOverlay(normalizedROI: roi, imageSize: image.size)
                            }
                        }

                        if session.lastCaptureFindings.isEmpty {
                            Text("No fields decoded on this frame.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(session.lastCaptureFindings.enumerated()), id: \.element.id) { index, finding in
                                    ScanResultRow(
                                        finding: finding,
                                        decision: session.payloadDecisions[finding.id]
                                    )
                                    .padding(.vertical, 8)
                                    if index < session.lastCaptureFindings.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.horizontal, AppDesign.cardPadding)
                        }
                    }
                } else {
                    MentraEmptyState(
                        symbol: "photo.on.rectangle.angled",
                        title: "No capture yet",
                        message: "Your next scan will appear here."
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: AppDesign.cornerRadius, style: .continuous))
        }
    }

    private var scanActionsBar: some View {
        HStack(spacing: 10) {
            Group {
                if session.isQRScanActive {
                    Button {
                        session.toggleQRScanning()
                    } label: {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(session.isScanInProgress)
                } else {
                    Button {
                        session.toggleQRScanning()
                    } label: {
                        Label("Start", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canStartLiveScan)
                }
            }

            Button {
                session.scan()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!session.canScan)

            Button {
                session.clearLastCaptureOnScanPage()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(session.lastScanPreviewImage == nil)
        }
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
