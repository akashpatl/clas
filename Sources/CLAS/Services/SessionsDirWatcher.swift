import Foundation

/// Watches `~/.claude/sessions/` and pushes parsed snapshots into a
/// `SessionStore`. Phase 1 implementation: polls every 500ms.
///
/// Polling vs FSEvents: 500ms latency is invisible for menu bar UI, the
/// directory holds <20 files in practice, and `Date.modified` skips to
/// "no change" cheaply. Phase 4's hook listener gives us sub-50ms updates
/// for the only transition that actually matters (starting to wait).
/// Upgrade to `FSEventStream` only if profiling shows polling cost.
@MainActor
final class SessionsDirWatcher {
    private let directory: URL
    private let store: SessionStore
    private var task: Task<Void, Never>?
    private var lastDirSnapshot: [URL: Date] = [:]
    /// Last successfully decoded session per file URL. Used to ride out
    /// transient decode failures (e.g. partial writes when Claude is
    /// updating a session file). Without this, a failed decode would
    /// silently drop the session for one tick, then reappear next tick,
    /// causing flicker and false `.appeared` events on every glitch.
    /// Evicted when the underlying file disappears.
    private var lastKnownGood: [URL: Session] = [:]

    init(store: SessionStore, directory: URL? = nil) {
        self.store = store
        self.directory = directory ?? Self.defaultDirectory
    }

    static var defaultDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".claude/sessions", directoryHint: .isDirectory)
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            await self?.scanOnce()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await self?.scanOnce()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Force an immediate rescan. Used by `HookHTTPListener` when a
    /// notification hook fires — we don't want to wait for the next 500ms
    /// poll tick to update the UI.
    func pingNow() {
        Task { [weak self] in
            await self?.scanOnce()
        }
    }

    private func scanOnce() async {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            store.apply(snapshot: [])
            return
        }

        let jsons = entries.filter { $0.pathExtension == "json" }

        var currentMtimes: [URL: Date] = [:]
        for url in jsons {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            currentMtimes[url] = values?.contentModificationDate ?? .distantPast
        }
        if currentMtimes == lastDirSnapshot { return }
        lastDirSnapshot = currentMtimes

        let decoder = JSONDecoder()
        let reader = TranscriptReader.shared
        var sessions: [Session] = []
        let liveURLs = Set(jsons)
        for url in jsons {
            guard let data = try? Data(contentsOf: url) else {
                if let cached = lastKnownGood[url] { sessions.append(cached) }
                continue
            }
            if var session = try? decoder.decode(Session.self, from: data) {
                session.lastMessage = reader.lastMessage(for: session)
                lastKnownGood[url] = session
                sessions.append(session)
            } else if let cached = lastKnownGood[url] {
                #if DEBUG
                print("SessionsDirWatcher: decode failed for \(url.lastPathComponent), serving cached")
                #endif
                sessions.append(cached)
            } else {
                #if DEBUG
                print("SessionsDirWatcher: decode failed for \(url.lastPathComponent), no cache")
                #endif
            }
        }
        // Evict cache entries whose underlying files are gone.
        lastKnownGood = lastKnownGood.filter { liveURLs.contains($0.key) }
        sessions.sort { $0.pid < $1.pid }
        store.apply(snapshot: sessions)
    }
}
