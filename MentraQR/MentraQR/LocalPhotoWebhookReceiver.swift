import Foundation
import Network

enum LocalPhotoWebhookError: LocalizedError {
    case invalidPort
    case listenerFailed(String)
    case timeout
    case noJPEG

    var errorDescription: String? {
        switch self {
        case .invalidPort: return "Invalid photo webhook port."
        case .listenerFailed(let detail): return "Photo webhook failed: \(detail)"
        case .timeout: return "Timed out waiting for glasses photo."
        case .noJPEG: return "Could not read JPEG from photo upload."
        }
    }
}

/// Loopback HTTP target for Mentra BLE photo relay (`BlePhotoUploadService` multipart POST).
final class LocalPhotoWebhookReceiver {
    private let queue = DispatchQueue(label: "com.local.mentraqr.photo-webhook")
    private var listener: NWListener?
    private var waiter: CheckedContinuation<Data, Error>?

    private static let webhookPort: UInt16 = 8802
    private static let receiveChunk = 2 * 1024 * 1024

    var webhookURL: URL {
        URL(string: "http://127.0.0.1:\(Self.webhookPort)/photo")!
    }

    func start() throws {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: Self.webhookPort) else {
            throw LocalPhotoWebhookError.invalidPort
        }

        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true

        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        var startupError: String?
        let sem = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                sem.signal()
            case let .failed(error), let .waiting(error):
                startupError = error.localizedDescription
                sem.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)
        self.listener = listener

        if sem.wait(timeout: .now() + 1) == .timedOut {
            stop()
            throw LocalPhotoWebhookError.listenerFailed("listener startup timed out")
        }
        if let startupError {
            stop()
            throw LocalPhotoWebhookError.listenerFailed(startupError)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        if let waiter {
            self.waiter = nil
            waiter.resume(throwing: CancellationError())
        }
    }

    func waitForJPEG(timeoutSeconds: TimeInterval = 50) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            waiter = continuation
            Task {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                if let pending = self.waiter {
                    self.waiter = nil
                    pending.resume(throwing: LocalPhotoWebhookError.timeout)
                }
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveChunk) { [weak self] data, _, isComplete, _ in
            guard let self else { return }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }

            if let body = self.completeHTTPBodyIfReady(buffer) {
                self.sendOKAndFinish(connection: connection, body: body)
                return
            }

            if isComplete {
                if let body = self.httpBody(from: buffer), let jpeg = Self.extractLargestJPEG(from: body) {
                    self.deliver(jpeg)
                } else if let waiter {
                    self.waiter = nil
                    waiter.resume(throwing: LocalPhotoWebhookError.noJPEG)
                }
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: buffer)
        }
    }

    private func completeHTTPBodyIfReady(_ buffer: Data) -> Data? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headers = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
        let contentLength = parseContentLength(headers)
        let bodyStart = headerEnd.upperBound
        let body = buffer[bodyStart...]
        if let contentLength, body.count >= contentLength {
            return body.prefix(contentLength)
        }
        if contentLength == nil, !body.isEmpty {
            return body
        }
        return nil
    }

    private func httpBody(from buffer: Data) -> Data? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        return buffer[headerEnd.upperBound...]
    }

    private func parseContentLength(_ headers: String) -> Int? {
        for line in headers.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private func sendOKAndFinish(connection: NWConnection, body: Data) {
        let responseBody = #"{"ok":true}"#
        let response =
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(responseBody.utf8.count)\r\nConnection: close\r\n\r\n\(responseBody)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
        if let jpeg = Self.extractLargestJPEG(from: body) {
            deliver(jpeg)
        } else if let waiter {
            self.waiter = nil
            waiter.resume(throwing: LocalPhotoWebhookError.noJPEG)
        }
    }

    private func deliver(_ jpeg: Data) {
        guard let waiter else { return }
        self.waiter = nil
        waiter.resume(returning: jpeg)
    }

    /// Picks the largest complete JPEG (multipart-safe; ends at EOI `FF D9`).
    static func extractLargestJPEG(from body: Data) -> Data? {
        var candidates: [Data] = []

        if body.count >= 2, body[body.startIndex] == 0xFF, body[body.startIndex + 1] == 0xD8 {
            if let end = jpegEndIndex(in: body, start: body.startIndex) {
                candidates.append(body[body.startIndex..<end])
            }
        }

        let marker = Data("Content-Type: image/jpeg\r\n\r\n".utf8)
        var search = body.startIndex
        while search < body.endIndex, let range = body.range(of: marker, in: search..<body.endIndex) {
            let start = range.upperBound
            if start + 1 < body.endIndex, body[start] == 0xFF, body[start + 1] == 0xD8,
               let end = jpegEndIndex(in: body, start: start) {
                candidates.append(body[start..<end])
                search = end
            } else {
                search = range.upperBound
            }
        }

        return candidates.max(by: { $0.count < $1.count })
    }

    private static func jpegEndIndex(in data: Data, start: Data.Index) -> Data.Index? {
        guard start < data.endIndex - 1 else { return nil }
        var i = start
        while i < data.endIndex - 1 {
            if data[i] == 0xFF, data[i + 1] == 0xD9 {
                return i + 2
            }
            i += 1
        }
        return data.endIndex
    }
}
