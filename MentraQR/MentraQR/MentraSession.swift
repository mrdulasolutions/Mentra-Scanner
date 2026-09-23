import Foundation
import MentraBluetoothSDK
import UIKit

@MainActor
final class MentraSession: NSObject, ObservableObject, MentraBluetoothSDKDelegate {
    @Published private(set) var connectionStatus = "Not connected"
    @Published private(set) var batteryText = "Battery: —"
    @Published private(set) var phoneLanIP = bestLocalIPv4Address() ?? "No LAN IP"
    @Published private(set) var phoneWifiSSID: String?
    @Published private(set) var phoneWifiAccess: WiFiSSIDAccessResult?
    @Published private(set) var fillLightStatus = ""
    @Published private(set) var glassesWifiSSID: String?
    @Published private(set) var glassesWifiLocalIP: String?
    @Published private(set) var wifiNetworkMatch: WiFiNetworkMatch = .unknown
    @Published private(set) var glassesWifiText = "Glasses Wi-Fi: unknown"
    private var glassesWifiIsConnected = false
    @Published private(set) var discoveredDevices: [Device] = []
    @Published var selectedDevice: Device?
    @Published private(set) var isScanningBLE = false
    @Published private(set) var isConnected = false
    @Published private(set) var isStreaming = false
    @Published private(set) var isQRScanActive = false
    @Published private(set) var streamStatus = "Idle"
    @Published private(set) var receiverLog = ""
    @Published private(set) var diagnosticLines: [String] = []
    @Published private(set) var previewFrameCount = 0
    @Published private(set) var previewHasVideo = false
    @Published private(set) var manualScanStatus = ""
    @Published private(set) var captureToast: String?
    @Published private(set) var lastScanPreviewImage: UIImage?
    @Published private(set) var lastScanLabelROI: CGRect?
    @Published private(set) var lastCaptureFindings: [ScanFinding] = []

    var isScanInProgress: Bool { frameScanDecoder.isStreamSnapshotInFlight }
    var canStartLiveScan: Bool {
        isConnected && glassesWifiConnected && !isQRScanActive && !isScanInProgress
    }
    var canScan: Bool {
        isConnected && glassesWifiConnected && isQRScanActive && !frameScanDecoder.isStreamSnapshotInFlight
    }

    var glassesWifiConnected: Bool {
        glassesWifiIsConnected
    }
    @Published private(set) var activeWhipURL = ""
    @Published private(set) var glassesFillLightOn = false
    @Published private(set) var sessionHistory: [String] = []
    @Published private(set) var sessionFindings: [String: ScanFinding] = [:]
    @Published private(set) var payloadDecisions: [String: PayloadDecision] = [:]
    @Published private(set) var wifiNetworks: [String] = []
    @Published var wifiSSID = ""
    @Published var wifiPassword = ""

    let whipReceiver = GStreamerWhipReceiver()
    let frameScanDecoder = FrameScanDecoder()
    let activityAnnouncer = ActivityAnnouncer()
    @Published var labelOCREnabled = ScanPreferences.labelOCREnabled

    private let payloadClassifier: any PayloadClassifying = CascadePayloadClassifier()
    private var payloadClassifyTasks: [String: Task<Void, Never>] = [:]
    private var fillLightSerial = 0
    private var fillLightDesiredOn = false
    private var fillLightKeepaliveTask: Task<Void, Never>?
    private var trackedFillLightRequestIds = Set<String>()

    private let sdk = MentraBluetoothSDK()
    private let whipProxy = WhipHeaderProxy()
    private let photoWebhook = LocalPhotoWebhookReceiver()
    private var scanSession: ScanSession?
    private var activeStreamId: String?
    private var directStreamStartTask: Task<Void, Never>?
    private var lastGlassesDisplayPayload: String?
    private var galleryModeConfigured = false
    private var publicWhipURL: String?
    private weak var captureLibrary: LabelCaptureLibrary?
    private var captureToastTask: Task<Void, Never>?
    private var wasGlassesConnected = false
    private enum Defaults {
        static let deviceName = "mentraqr.defaultDevice.name"
        static let deviceId = "mentraqr.defaultDevice.identifier"
        static let deviceModel = "mentraqr.defaultDevice.model"
    }

    func bindCaptureLibrary(_ library: LabelCaptureLibrary) {
        captureLibrary = library
        frameScanDecoder.onLabelSnapshotCaptured = { [weak self] image, findings, reason, originalJPEG, labelROI in
            library.persistLabelSnapshot(
                image: image,
                findings: findings,
                triggerReason: reason,
                originalJPEG: originalJPEG,
                labelROI: labelROI
            )
            self?.lastScanPreviewImage = UIImage(cgImage: image)
            self?.lastScanLabelROI = labelROI
            self?.lastCaptureFindings = findings
            self?.appendDiagnostic("DB: saved stream frame (\(findings.count) parsed fields)")
        }
        frameScanDecoder.onStreamSnapshotSaved = { [weak self] count in
            self?.showCaptureToast(fieldCount: count)
        }
    }

    override init() {
        super.init()
        sdk.delegate = self
        whipReceiver.onStateChanged = { [weak self] message in
            Task { @MainActor in
                self?.appendReceiverLog(message)
            }
        }
        whipReceiver.onFrameRendered = { [weak self] in
            Task { @MainActor in
                self?.markPreviewFrame()
            }
        }
        whipReceiver.onFrameImage = { [weak self] image in
            Task { @MainActor in
                self?.frameScanDecoder.process(image)
            }
        }
        frameScanDecoder.onVisibleSetChanged = { [weak self] findings in
            Task { @MainActor in
                self?.updateGlassesDisplay(for: findings)
            }
        }
        frameScanDecoder.onNewFinding = { [weak self] finding in
            Task { @MainActor in
                self?.recordFinding(finding)
            }
        }
        frameScanDecoder.onScanDebug = { [weak self] message in
            Task { @MainActor in
                self?.appendDiagnostic("Scan: \(message)")
            }
        }
        requestPhoneWiFiPermission()
        restoreDefaultDevice()
        applyGlassesState(sdk.glasses)
        wasGlassesConnected = sdk.glasses.connected
        applySdkState(sdk.sdkState)
        frameScanDecoder.setLabelOCREnabled(ScanPreferences.labelOCREnabled)
    }

    func setLabelOCREnabled(_ enabled: Bool) {
        ScanPreferences.labelOCREnabled = enabled
        labelOCREnabled = enabled
        frameScanDecoder.setLabelOCREnabled(enabled)
    }

    deinit {
        photoWebhook.stop()
        whipProxy.stop()
        whipReceiver.stop()
    }

    func refreshPhoneIP() {
        phoneLanIP = bestLocalIPv4Address() ?? "No LAN IP"
        recomputeWifiMatch()
    }

    func refreshPhoneNetwork() {
        refreshPhoneIP()
        Task {
            let result = await WiFiSSIDReader.shared.fetchSSIDWithAuthorization()
            phoneWifiAccess = result
            switch result {
            case let .ssid(ssid):
                phoneWifiSSID = ssid
            case .notOnWiFi, .locationNotDetermined:
                phoneWifiSSID = nil
            case .locationDenied, .locationRestricted:
                phoneWifiSSID = nil
            }
            recomputeWifiMatch()
        }
    }

    func requestPhoneWiFiPermission() {
        WiFiSSIDReader.shared.requestAuthorizationIfNeeded()
        refreshPhoneNetwork()
    }

    func startBLEScan() {
        discoveredDevices = []
        selectedDevice = nil
        isScanningBLE = true
        connectionStatus = "Scanning for Mentra Live…"
        do {
            scanSession?.stop()
            scanSession = try sdk.scan(model: .mentraLive, timeout: 12) { [weak self] devices in
                Task { @MainActor in
                    self?.discoveredDevices = devices
                    if self?.selectedDevice == nil {
                        self?.selectedDevice = devices.first
                    }
                }
            }
        } catch {
            isScanningBLE = false
            connectionStatus = "Scan failed: \(error.localizedDescription)"
        }
    }

    func stopBLEScan() {
        scanSession?.stop()
        scanSession = nil
        isScanningBLE = false
    }

    func connectSelected() {
        guard let device = selectedDevice ?? discoveredDevices.first else {
            connectionStatus = "Select glasses from the scan list first."
            return
        }
        connect(device)
    }

    func connectDefault() {
        Task {
            do {
                try sdk.connectDefault()
                connectionStatus = "Connecting to saved glasses…"
            } catch {
                connectionStatus = "Reconnect failed: \(error.localizedDescription)"
            }
        }
    }

    func connect(_ device: Device) {
        selectedDevice = device
        persistDefaultDevice(device)
        Task {
            do {
                try sdk.connect(to: device)
                connectionStatus = "Connecting to \(device.name)…"
            } catch {
                connectionStatus = "Connect failed: \(error.localizedDescription)"
            }
        }
    }

    func disconnect() {
        Task {
            captureToastTask?.cancel()
            await setGlassesFillLight(false)
            await stopQRScanning()
            sdk.disconnect()
            connectionStatus = "Disconnected"
            isConnected = false
            galleryModeConfigured = false
        }
    }

    /// Live WHIP preview (Scan tab auto-starts). Advanced tab can stop/start manually.
    func toggleQRScanning() {
        if isScanInProgress {
            manualScanStatus = "Wait for save to finish."
            return
        }
        if isQRScanActive {
            manualScanStatus = "Stopping live scan…"
            Task { await stopQRScanning() }
        } else {
            manualScanStatus = "Starting live scan…"
            Task { await startQRScanning() }
        }
    }

    /// Saves the current live stream frame (WHIP stays running).
    func scan() {
        guard isQRScanActive else {
            manualScanStatus = "Tap Start live to begin."
            return
        }
        manualScanStatus = "Saving frame…"
        frameScanDecoder.captureStreamFrameNow(reason: "manual Scan (stream frame)")
    }

    func clearLastCaptureOnScanPage() {
        lastScanPreviewImage = nil
        lastScanLabelROI = nil
        lastCaptureFindings = []
        manualScanStatus = ""
    }

    func clearSessionFindings() {
        sessionHistory = []
        sessionFindings = [:]
        payloadDecisions = [:]
        payloadClassifyTasks.values.forEach { $0.cancel() }
        payloadClassifyTasks.removeAll()
    }

    private func showCaptureToast(fieldCount: Int) {
        captureToastTask?.cancel()
        captureToast = fieldCount > 0 ? "Label captured · \(fieldCount) field\(fieldCount == 1 ? "" : "s")" : "Frame saved"
        manualScanStatus = captureToast ?? ""
        activityAnnouncer.notifyLabelCaptured(fieldCount: fieldCount)
        captureToastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                self?.captureToast = nil
            }
        }
    }

    func toggleGlassesFillLight() {
        fillLightDesiredOn = !fillLightDesiredOn
        fillLightSerial += 1
        let serial = fillLightSerial
        Task {
            await applyFillLightState(serial: serial, userInitiated: true)
        }
    }

    func setGlassesFillLight(_ enabled: Bool, serial: Int? = nil) async {
        fillLightDesiredOn = enabled
        if serial == nil {
            fillLightSerial += 1
        }
        let activeSerial = serial ?? fillLightSerial
        await applyFillLightState(serial: activeSerial, userInitiated: false)
    }

    private func applyFillLightState(serial: Int, userInitiated: Bool) async {
        if serial != fillLightSerial {
            return
        }
        stopFillLightKeepalive()

        guard isConnected else {
            fillLightStatus = "Connect to glasses to use the fill light."
            glassesFillLightOn = false
            fillLightDesiredOn = false
            return
        }

        if fillLightDesiredOn {
            if !glassesReady {
                fillLightStatus = "Waiting for glasses to finish booting…"
                let ready = await waitForGlassesReady(timeoutSeconds: 8)
                guard ready else {
                    fillLightStatus = "Glasses not ready yet — try Light again in a few seconds."
                    appendDiagnostic("Fill light: glasses not ready (fullyBooted=false)")
                    if userInitiated {
                        fillLightDesiredOn = false
                    }
                    return
                }
            }

            fillLightStatus = "Turning fill light on…"
            appendDiagnostic("Fill light → ON (white, \(GlassesFillLight.solidOnDurationMs)ms solid + keepalive)")
            try? await Task.sleep(nanoseconds: GlassesFillLight.authoritySettleNanoseconds)

            do {
                _ = try await sendFillLightOff()
                try? await Task.sleep(nanoseconds: GlassesFillLight.betweenCommandsNanoseconds)
                try await sendFillLightOn(retryLabel: "primary")
                if serial != fillLightSerial { return }
                glassesFillLightOn = true
                fillLightStatus = "Fill light on (glasses white LED)"
                activityAnnouncer.announceFillLight(on: true)
                startFillLightKeepalive(serial: serial)
            } catch {
                if serial != fillLightSerial { return }
                appendDiagnostic("Fill light ON failed, retrying once: \(error.localizedDescription)")
                try? await Task.sleep(nanoseconds: 600_000_000)
                do {
                    try await sendFillLightOn(retryLabel: "retry")
                    if serial != fillLightSerial { return }
                    glassesFillLightOn = true
                    fillLightStatus = "Fill light on (glasses white LED)"
                    activityAnnouncer.announceFillLight(on: true)
                    startFillLightKeepalive(serial: serial)
                } catch {
                    glassesFillLightOn = false
                    fillLightDesiredOn = false
                    fillLightStatus = "Fill light failed: \(error.localizedDescription)"
                    appendDiagnostic("Fill light failed: \(error.localizedDescription)")
                }
            }
        } else {
            fillLightStatus = "Turning fill light off…"
            appendDiagnostic("Fill light → OFF")
            do {
                _ = try await sendFillLightOff()
                try? await Task.sleep(nanoseconds: GlassesFillLight.betweenCommandsNanoseconds)
                _ = try await sendFillLightOff()
                if serial != fillLightSerial { return }
                glassesFillLightOn = false
                fillLightStatus = ""
                activityAnnouncer.announceFillLight(on: false)
            } catch {
                if serial != fillLightSerial { return }
                glassesFillLightOn = false
                fillLightStatus = "Fill light off may have failed: \(error.localizedDescription)"
                appendDiagnostic("Fill light OFF error: \(error.localizedDescription)")
            }
        }
    }

    private var glassesReady: Bool {
        sdk.glasses.ready
    }

    private func waitForGlassesReady(timeoutSeconds: Int) async -> Bool {
        if glassesReady { return true }
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if glassesReady { return true }
        }
        return glassesReady
    }

    private func sendFillLightOn(retryLabel: String) async throws -> RgbLedControlResponseEvent {
        let requestId = "fill-light-on-\(retryLabel)-\(Int(Date().timeIntervalSince1970 * 1000))"
        trackedFillLightRequestIds.insert(requestId)
        defer { trackedFillLightRequestIds.remove(requestId) }
        let event = try await sdk.rgbLedControl(GlassesFillLight.onRequest(requestId: requestId))
        appendDiagnostic("RGB LED ON (\(retryLabel)): state=\(event.state) error=\(event.errorCode ?? "—")")
        guard event.state == "success" else {
            throw NSError(
                domain: "MentraQR",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: event.errorCode ?? "RGB LED on failed"]
            )
        }
        return event
    }

    @discardableResult
    private func sendFillLightOff() async throws -> RgbLedControlResponseEvent {
        let requestId = "fill-light-off-\(Int(Date().timeIntervalSince1970 * 1000))"
        trackedFillLightRequestIds.insert(requestId)
        defer { trackedFillLightRequestIds.remove(requestId) }
        let event = try await sdk.rgbLedControl(GlassesFillLight.offRequest(requestId: requestId))
        appendDiagnostic("RGB LED OFF: state=\(event.state) error=\(event.errorCode ?? "—")")
        guard event.state == "success" else {
            throw NSError(
                domain: "MentraQR",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: event.errorCode ?? "RGB LED off failed"]
            )
        }
        return event
    }

    private func startFillLightKeepalive(serial: Int) {
        stopFillLightKeepalive()
        fillLightKeepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: GlassesFillLight.keepaliveIntervalSeconds * 1_000_000_000)
                guard let self else { return }
                guard self.fillLightDesiredOn, self.glassesFillLightOn, self.isConnected else { return }
                guard serial == self.fillLightSerial else { return }
                self.appendDiagnostic("Fill light keepalive refresh")
                do {
                    _ = try await self.sendFillLightOn(retryLabel: "keepalive")
                } catch {
                    self.appendDiagnostic("Fill light keepalive failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func stopFillLightKeepalive() {
        fillLightKeepaliveTask?.cancel()
        fillLightKeepaliveTask = nil
    }

    private func refreshFillLightAfterStreamIfNeeded() {
        guard fillLightDesiredOn, glassesFillLightOn else { return }
        fillLightSerial += 1
        let serial = fillLightSerial
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await applyFillLightState(serial: serial, userInitiated: false)
        }
    }

    func requestWifiScan() {
        Task {
            guard isConnected else {
                connectionStatus = "Connect to glasses before scanning Wi-Fi."
                return
            }
            do {
                let networks = try await sdk.requestWifiScan()
                wifiNetworks = networks.map(\.ssid).filter { !$0.isEmpty }
                if wifiNetworks.isEmpty {
                    wifiNetworks = sdk.sdkState.wifiScanResults.map(\.ssid).filter { !$0.isEmpty }
                }
            } catch {
                connectionStatus = "Wi-Fi scan failed: \(error.localizedDescription)"
            }
        }
    }

    func sendWifiCredentials() {
        let ssid = wifiSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ssid.isEmpty else {
            connectionStatus = "Enter a Wi-Fi network name."
            return
        }
        Task {
            guard isConnected else { return }
            do {
                _ = try await sdk.sendWifiCredentials(ssid: ssid, password: wifiPassword)
                connectionStatus = "Sent Wi-Fi credentials for \(ssid)."
            } catch {
                connectionStatus = "Wi-Fi connect failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - MentraBluetoothSDKDelegate

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didUpdateGlasses glasses: GlassesRuntimeState) {
        applyGlassesState(glasses)
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didUpdateSdkState sdkState: PhoneSdkRuntimeState) {
        applySdkState(sdkState)
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didUpdateScan scan: BluetoothScanState) {
        isScanningBLE = scan.active
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didDiscover device: Device) {
        if !discoveredDevices.contains(where: { $0.identifier == device.identifier }) {
            discoveredDevices.append(device)
        }
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didReceive event: BluetoothEvent) {
        switch event {
        case let .buttonPress(button):
            handleButtonPress(button)
        case let .wifiStatus(event):
            updateWifiDescription(event.status)
        case let .streamStatus(event):
            handleStreamStatus(event.status)
        case let .rgbLedControlResponse(event):
            appendDiagnostic("SDK rgb_led: state=\(event.state) id=\(event.requestId) error=\(event.errorCode ?? "—")")
            if trackedFillLightRequestIds.contains(event.requestId) {
                if event.state == "success", event.requestId.contains("fill-light-on") {
                    glassesFillLightOn = true
                }
                if event.state != "success" {
                    appendDiagnostic("Fill light SDK error: \(event.errorCode ?? event.state)")
                }
            }
        default:
            break
        }
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didFail error: BluetoothSdkError) {
        connectionStatus = error.localizedDescription
        appendDiagnostic("SDK error: \(error.localizedDescription)")
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didLog message: String) {
        appendDiagnostic("SDK: \(message)")
    }

    func clearDiagnostics() {
        diagnosticLines = []
    }

    // MARK: - Legacy WHIP streaming (Advanced / SDK)

    private func startQRScanning() async {
        guard isConnected else {
            streamStatus = "Connect to glasses first."
            return
        }
        guard glassesWifiConnected else {
            streamStatus = "Glasses need Wi-Fi on the same network as this iPhone."
            return
        }
        refreshPhoneIP()
        guard let host = bestLocalIPv4Address() else {
            streamStatus = "No phone LAN IP. Join Wi-Fi so the glasses can reach this phone."
            return
        }

        frameScanDecoder.reset()
        previewFrameCount = 0
        previewHasVideo = false
        manualScanStatus = ""
        streamStatus = "Starting phone receiver…"
        isQRScanActive = true
        appendDiagnostic("Scan start — phone LAN \(host)")

        do {
            try await ensureGalleryModeOff()
            appendDiagnostic("Gallery mode off (button reports to app)")
            try startPhoneReceiver(advertisedHost: host)
            let streamId = "mentraqr-\(Int(Date().timeIntervalSince1970 * 1000))"
            guard let whipUrl = publicWhipURL else {
                throw NSError(domain: "MentraQR", code: 3, userInfo: [NSLocalizedDescriptionKey: "WHIP URL missing"])
            }
            activeStreamId = streamId
            activeWhipURL = whipUrl
            streamStatus = "Starting camera stream…"
            appendDiagnostic("WHIP URL for glasses: \(whipUrl)")

            directStreamStartTask?.cancel()
            directStreamStartTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard let self, self.isQRScanActive, self.activeStreamId == streamId else { return }
                do {
                    let started = try await self.sdk.startStream(
                        StreamRequest(
                            streamUrl: whipUrl,
                            streamId: streamId,
                            video: StreamVideoConfig(fps: 15)
                        )
                    )
                    self.isStreaming = true
                    self.streamStatus = "Live — scan labels & barcodes"
                    self.activityAnnouncer.announceLiveScan(started: true)
                    self.appendDiagnostic("startStream OK: \(started.status.state.rawValue)")
                    self.refreshFillLightAfterStreamIfNeeded()
                } catch {
                    self.streamStatus = "Stream failed: \(error.localizedDescription)"
                    self.activityAnnouncer.announceStreamStatus(self.streamStatus)
                    self.appendDiagnostic("startStream failed: \(error.localizedDescription)")
                    await self.stopQRScanning()
                }
            }
        } catch {
            streamStatus = "Receiver failed: \(error.localizedDescription)"
            appendDiagnostic("Receiver failed: \(error.localizedDescription)")
            await stopQRScanning()
        }
    }

    private func stopQRScanning() async {
        isQRScanActive = false
        directStreamStartTask?.cancel()
        directStreamStartTask = nil
        frameScanDecoder.reset()
        sessionHistory = []
        sessionFindings = [:]
        payloadDecisions = [:]
        payloadClassifyTasks.values.forEach { $0.cancel() }
        payloadClassifyTasks.removeAll()
        lastGlassesDisplayPayload = nil

        if isStreaming || activeStreamId != nil {
            do {
                _ = try await sdk.stopStream()
            } catch {
                appendReceiverLog("stopStream: \(error.localizedDescription)")
            }
        }
        isStreaming = false
        activeStreamId = nil
        publicWhipURL = nil
        activeWhipURL = ""
        previewFrameCount = 0
        previewHasVideo = false
        manualScanStatus = ""
        whipProxy.stop()
        whipReceiver.stop()
        streamStatus = "Scanning stopped"
        activityAnnouncer.announceLiveScan(started: false)
        appendDiagnostic("Scan stopped (fill light unchanged — use Light button)")
        try? await sdk.clearDisplay()
    }

    private func startPhoneReceiver(advertisedHost: String) throws {
        whipProxy.stop()
        whipReceiver.stop()

        let portPairs: [(publicPort: Int, backendPort: Int)] = [
            (8190, 8191),
            (8192, 8193),
            (8194, 8195),
        ]
        var lastError: Error?
        for pair in portPairs {
            do {
                try whipReceiver.start(withAdvertisedHost: "127.0.0.1", port: pair.backendPort)
                try whipProxy.start(listenPort: UInt16(pair.publicPort), backendPort: UInt16(pair.backendPort))
                publicWhipURL = "http://\(advertisedHost):\(pair.publicPort)/whip/endpoint"
                activeWhipURL = publicWhipURL ?? ""
                streamStatus = "Receiver at \(publicWhipURL ?? "")"
                appendDiagnostic("GStreamer WHIP listening on ports \(pair.publicPort)→\(pair.backendPort)")
                return
            } catch {
                lastError = error
                whipProxy.stop()
                whipReceiver.stop()
            }
        }
        throw lastError ?? NSError(domain: "MentraQR", code: 2, userInfo: [NSLocalizedDescriptionKey: "No WHIP port available"])
    }

    private func ensureGalleryModeOff() async throws {
        guard !galleryModeConfigured else { return }
        _ = try await sdk.setGalleryModeEnabled(false)
        galleryModeConfigured = true
    }

    private func handleButtonPress(_ button: ButtonPressEvent) {
        let type = button.pressType.lowercased()
        guard type.contains("short") || type == "press" else { return }
        // Hi-res capture is triggered from stream detection; button reserved for future SDK hooks.
    }

    private func handleStreamStatus(_ status: StreamStatus) {
        appendDiagnostic("stream_status: \(status.state.rawValue)")
        switch status.state {
        case .streaming, .reconnected, .reconnecting, .initializing:
            isStreaming = true
            if streamStatus.hasPrefix("Starting") {
                streamStatus = "Live — scan labels & barcodes"
            }
        case .stopped, .stopping, .error, .reconnectFailed:
            if isQRScanActive {
                streamStatus = "Stream ended (\(status.state.rawValue))"
            }
            isStreaming = false
            if case let .error(_, details, _, _) = status {
                appendDiagnostic("stream error: \(details)")
            }
        }
    }

    private func markPreviewFrame() {
        previewFrameCount += 1
        previewHasVideo = true
        if previewFrameCount == 1 {
            appendDiagnostic("First video frame rendered on phone")
            streamStatus = "Live — scan labels & barcodes"
        }
    }

    private func applyGlassesState(_ glasses: GlassesRuntimeState) {
        let connected = glasses.connected
        if connected != wasGlassesConnected {
            wasGlassesConnected = connected
            activityAnnouncer.announceConnection(connected: connected, deviceName: selectedDevice?.name)
        }
        isConnected = connected
        switch glasses.connection {
        case .connected:
            connectionStatus = "Connected"
            Task {
                try? await ensureGalleryModeOff()
            }
        case .connecting, .bonding, .scanning:
            connectionStatus = "Connecting…"
        case .disconnected:
            if !isScanningBLE {
                connectionStatus = "Not connected"
            }
            if isQRScanActive {
                Task { await stopQRScanning() }
            }
        }

        if let level = glasses.battery?.level {
            let charging = glasses.battery?.charging == true
            batteryText = "Battery: \(level)%\(charging ? " (charging)" : "")"
        }
        if let wifi = glasses.wifi {
            updateWifiDescription(wifi)
        }
    }

    private func applySdkState(_: PhoneSdkRuntimeState) {
        // Glasses connection state is driven by `didUpdateGlasses`.
    }

    private func updateWifiDescription(_ status: WifiStatus) {
        switch status {
        case .disconnected:
            glassesWifiIsConnected = false
            glassesWifiSSID = nil
            glassesWifiLocalIP = nil
            glassesWifiText = "Glasses Wi-Fi: disconnected"
        case let .connected(ssid, localIp):
            glassesWifiIsConnected = true
            glassesWifiSSID = ssid
            glassesWifiLocalIP = localIp
            let ip = localIp ?? "unknown IP"
            glassesWifiText = "Glasses Wi-Fi: connected to \(ssid) (\(ip))"
        }
        recomputeWifiMatch()
    }

    private func recomputeWifiMatch() {
        let phoneSSID = phoneWifiSSID
        wifiNetworkMatch = PhoneNetworkInfo.compareNetworks(
            phoneSSID: phoneSSID,
            glassesSSID: glassesWifiSSID,
            glassesConnected: glassesWifiIsConnected,
            phoneAccess: phoneWifiAccess
        )
    }

    private func recordFinding(_ finding: ScanFinding) {
        guard finding.captureContext == .labelSnapshot else { return }
        let key = finding.normalizedKey
        if let parcel = finding.parsed?.parcelKey {
            mergeParcelAlias(from: key, parcelKey: "parcel:\(parcel)")
        }
        guard !sessionHistory.contains(key) else {
            sessionFindings[key] = finding
            return
        }
        sessionHistory.insert(key, at: 0)
        sessionFindings[key] = finding
        sessionHistory = Array(sessionHistory.prefix(50))
        classifyFindingIfNeeded(finding)
    }

    private func mergeParcelAlias(from findingKey: String, parcelKey: String) {
        if let existingDecision = payloadDecisions[parcelKey] {
            payloadDecisions[findingKey] = existingDecision
        }
        if sessionHistory.contains(parcelKey), !sessionHistory.contains(findingKey) {
            // Prefer single parcel row in history.
            return
        }
    }

    private func latestOcrExcerpt() -> String? {
        frameScanDecoder.visibleFindings
            .first(where: { $0.source == .ocr })
            .map(\.rawText)
    }

    private func classifyFindingIfNeeded(_ finding: ScanFinding) {
        let key = finding.normalizedKey
        guard payloadDecisions[key] == nil else { return }
        payloadClassifyTasks[key]?.cancel()
        let ocr = latestOcrExcerpt()
        let context = ScanClassificationContext(finding: finding, relatedOcrExcerpt: ocr)
        payloadClassifyTasks[key] = Task { [weak self] in
            guard let self else { return }
            let decision = await payloadClassifier.classify(context: context)
            await MainActor.run {
                self.payloadDecisions[key] = decision
                if let parcel = finding.parsed?.parcelKey {
                    self.payloadDecisions["parcel:\(parcel)"] = decision
                }
                self.payloadClassifyTasks.removeValue(forKey: key)
            }
        }
    }

    private func updateGlassesDisplay(for findings: [ScanFinding]) {
        let summary = glassesSummary(for: findings)
        guard summary != lastGlassesDisplayPayload else { return }
        lastGlassesDisplayPayload = summary
        Task {
            if findings.isEmpty {
                try? await sdk.displayText("Scanning…", x: 0, y: 0, size: 20)
            } else {
                try? await sdk.displayText(summary, x: 0, y: 0, size: 20)
            }
        }
    }

    private func glassesSummary(for findings: [ScanFinding]) -> String {
        guard !findings.isEmpty else { return "Scanning…" }
        let count = findings.count
        let first = findings[0]
        let decisionKey = first.normalizedKey
        if let parsed = first.parsed, let carrier = parsed.carrier {
            var head = carrier
            if let tracking = parsed.trackingId {
                let tail = tracking.count > 12 ? String(tracking.suffix(8)) : tracking
                head += " · \(tail)"
            }
            if head.count > 28 { head = String(head.prefix(25)) + "…" }
            return head
        }
        if count == 1, let decision = payloadDecisions[decisionKey] {
            var head = decision.label
            if decision.reviewRecommended {
                head += " · review?"
            }
            if head.count > 28 {
                head = String(head.prefix(25)) + "…"
            }
            return head
        }
        let trimmed = first.rawText.count > 28 ? String(first.rawText.prefix(25)) + "…" : first.rawText
        if count == 1 {
            return trimmed
        }
        return "\(count) codes: \(trimmed)"
    }

    private func appendReceiverLog(_ message: String) {
        receiverLog = message
        if message.contains("error") || message.contains("Error") || message.contains("Listening") || message.contains("Rendered") {
            appendDiagnostic("GStreamer: \(message)")
        }
    }

    private func appendDiagnostic(_ message: String) {
        AppDiagnostics.log(message) { line in
            self.diagnosticLines.insert(line, at: 0)
            self.diagnosticLines = Array(self.diagnosticLines.prefix(80))
        }
    }

    private func persistDefaultDevice(_ device: Device) {
        let defaults = UserDefaults.standard
        defaults.set(device.name, forKey: Defaults.deviceName)
        defaults.set(device.identifier, forKey: Defaults.deviceId)
        defaults.set(device.model.rawValue, forKey: Defaults.deviceModel)
        sdk.setDefaultDevice(device)
    }

    private func restoreDefaultDevice() {
        let defaults = UserDefaults.standard
        guard let name = defaults.string(forKey: Defaults.deviceName),
              let identifier = defaults.string(forKey: Defaults.deviceId) else {
            return
        }
        let modelRaw = defaults.string(forKey: Defaults.deviceModel)
        let model = modelRaw.flatMap { DeviceModel(rawValue: $0) } ?? .mentraLive
        let device = Device(model: model, name: name, identifier: identifier)
        sdk.setDefaultDevice(device)
    }
}
