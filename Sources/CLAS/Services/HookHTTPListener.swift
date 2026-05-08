import Foundation
import Network
import OSLog

private let log = Logger(subsystem: "CLAS", category: "hook")

/// Tiny localhost HTTP server. The Notification hook script POSTs JSON
/// payloads here; we trigger an immediate filesystem rescan so the UI
/// updates within a few ms instead of waiting up to 500ms for the next
/// poll tick.
///
/// Implementation notes:
///  - Binds to loopback only (`.requiredInterfaceType = .loopback`); not
///    reachable from other machines.
///  - Port is kernel-assigned (avoids collisions with whatever else the
///    user runs); persisted to `~/Library/Application Support/CLAS/port`
///    so the hook script can find us.
///  - Accepts any HTTP body; we only use receipt of a request as the
///    "ping me now" signal. The body could be parsed for richer text,
///    but the filesystem already has everything we need.
@MainActor
final class HookHTTPListener {
    /// Total request size cap. Generous for any plausible Claude hook
    /// payload (well under 4KB), tight enough that a buggy or hostile
    /// local sender cannot OOM us by streaming forever.
    private static let maxRequestBytes = 1 * 1024 * 1024
    /// Per-connection deadline. A keep-alive client that sends headers
    /// and never closes would otherwise leak the NWConnection.
    private static let receiveTimeout: Duration = .seconds(5)

    private let onPing: (Data?) -> Void
    private var listener: NWListener?

    init(onPing: @escaping (Data?) -> Void) {
        self.onPing = onPing
    }

    var portFileURL: URL {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return support.appending(path: "CLAS/port")
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.requiredInterfaceType = .loopback
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.handle(conn) }
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let listener else { return }
                Task { @MainActor in
                    switch state {
                    case .ready:
                        if let port = listener.port {
                            self?.persistPort(port.rawValue)
                            log.info("listener ready on 127.0.0.1:\(port.rawValue)")
                        }
                    case .failed(let error):
                        log.error("listener failed: \(String(describing: error), privacy: .public)")
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            log.error("listener init error: \(String(describing: error), privacy: .public)")
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        Task { @MainActor [weak self] in
            let body = await Self.receiveRequest(conn)
            log.info("hook ping: \(body?.count ?? 0) bytes")
            self?.onPing(body)
            let response = Data("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            conn.send(content: response, completion: .contentProcessed { _ in
                conn.cancel()
            })
        }
    }

    /// Reads a small HTTP request from `conn` and returns the body.
    /// Bounded by `maxRequestBytes` and `receiveTimeout` so a stuck or
    /// hostile connection cannot grow indefinitely or hold the task open.
    private static func receiveRequest(_ conn: NWConnection) async -> Data? {
        // The deadline timer cancels the connection itself, which forces
        // any pending `conn.receive` to fire (typically with no data and
        // isComplete=false), breaking the loop cleanly.
        let timeoutTask = Task<Void, Never> {
            try? await Task.sleep(for: receiveTimeout)
            if !Task.isCancelled { conn.cancel() }
        }
        defer { timeoutTask.cancel() }

        var buffer = Data()
        while true {
            let chunk: (Data?, Bool) = await withCheckedContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, _ in
                    cont.resume(returning: (data, isComplete))
                }
            }
            if let data = chunk.0 { buffer.append(data) }
            if buffer.count > maxRequestBytes {
                log.error("hook payload exceeded \(maxRequestBytes) bytes; dropping")
                return nil
            }
            if isRequestComplete(buffer) || chunk.1 {
                return extractBody(buffer)
            }
            // Connection cancelled (timeout or peer hangup) and nothing more
            // to read: bail rather than loop forever on empty receives.
            if chunk.0 == nil && !chunk.1 && buffer.isEmpty {
                return nil
            }
        }
    }

    private static let crlfcrlf = Data([0x0D, 0x0A, 0x0D, 0x0A])

    private static func isRequestComplete(_ data: Data) -> Bool {
        guard let headerEnd = data.range(of: crlfcrlf) else { return false }
        let bodyStart = headerEnd.upperBound
        guard let headers = String(data: data.prefix(upTo: headerEnd.lowerBound), encoding: .utf8)
        else { return true }
        for line in headers.split(separator: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let raw = Int(line.dropFirst("content-length:".count)
                    .trimmingCharacters(in: .whitespaces)) ?? 0
                // Clamp to maxRequestBytes so an Int.max Content-Length
                // can't make us wait for bytes that will never arrive.
                let n = min(max(raw, 0), maxRequestBytes)
                return data.count >= bodyStart + n
            }
        }
        return true // no content-length: assume done after headers
    }

    private static func extractBody(_ data: Data) -> Data? {
        guard let range = data.range(of: crlfcrlf) else { return nil }
        return data.subdata(in: range.upperBound..<data.count)
    }

    private func persistPort(_ port: UInt16) {
        let url = portFileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? "\(port)\n".write(to: url, atomically: true, encoding: .utf8)
    }
}
