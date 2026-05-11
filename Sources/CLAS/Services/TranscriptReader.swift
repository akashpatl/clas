import Foundation

/// A single visible message in the transcript — either user-typed or
/// assistant-spoken. Tool calls, tool results, and thinking blocks are
/// excluded since they aren't conversation the user expects to see.
struct LastMessage: Hashable {
    enum Role: String, Hashable { case user, assistant }
    let role: Role
    let text: String
}

/// Extracts the last conversational message from a session's JSONL transcript.
///
/// User vs assistant flavours:
///   - `"type":"user"` with `message.content` as a String  → user typed it
///   - `"type":"user"` with `message.content` as Array     → tool_result echo, skip
///   - `"type":"assistant"` with `message.content[]` containing a `text` block
///                                                         → claude said it
///   - assistant messages with only `tool_use` blocks      → skip, keep scanning back
///
/// Performance: same tail-window strategy as before — seek to the last
/// `tailWindow` bytes of the transcript file and walk lines from the end.
/// Cached by sessionId, invalidated by file mtime.
@MainActor
final class TranscriptReader {
    static let shared = TranscriptReader()

    private struct CacheEntry {
        let mtime: Date
        let message: LastMessage?
    }

    private var cache: [String: CacheEntry] = [:]
    private var pathByKey: [String: URL] = [:]
    /// Bumped from 64KB → 256KB: long tool-use chains can fill the last
    /// 64KB with `tool_use`/`tool_result` lines and push the actual last
    /// conversational message outside the window, causing the preview
    /// to read "No messages yet" despite plenty of real conversation.
    private let tailWindow: Int = 256 * 1024
    private let projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/projects", directoryHint: .isDirectory)
        .standardizedFileURL

    func lastMessage(for session: Session) -> LastMessage? {
        guard let url = transcriptURL(for: session) else { return nil }

        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? .distantPast

        if let cached = cache[session.sessionId], cached.mtime == mtime {
            return cached.message
        }

        let message = extractLastMessage(at: url)
        cache[session.sessionId] = CacheEntry(mtime: mtime, message: message)
        return message
    }

    private func transcriptURL(for session: Session) -> URL? {
        if let cached = pathByKey[session.sessionId] { return cached }

        // Convention: cwd path with `/` → `-`, then `{sessionId}.jsonl`.
        let key = session.cwd.replacingOccurrences(of: "/", with: "-")
        let direct = projectsRoot
            .appending(path: key, directoryHint: .isDirectory)
            .appending(path: "\(session.sessionId).jsonl")
        if FileManager.default.fileExists(atPath: direct.path), isInsideProjectsRoot(direct) {
            pathByKey[session.sessionId] = direct
            return direct
        }

        // Fallback: scan all project dirs for a file named {sessionId}.jsonl.
        let fm = FileManager.default
        if let dirs = try? fm.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil) {
            for dir in dirs {
                let candidate = dir.appending(path: "\(session.sessionId).jsonl")
                if fm.fileExists(atPath: candidate.path), isInsideProjectsRoot(candidate) {
                    pathByKey[session.sessionId] = candidate
                    return candidate
                }
            }
        }
        return nil
    }

    /// Defence in depth against a malicious `session.cwd` that resolves
    /// upward via `..` components — confirm the resolved file lives under
    /// `~/.claude/projects/` before opening it. Belt-and-braces given the
    /// `/` → `-` substitution already neuters most traversal attempts.
    private func isInsideProjectsRoot(_ url: URL) -> Bool {
        let resolved = url.standardizedFileURL.path
        let rootPath = projectsRoot.path
        return resolved.hasPrefix(rootPath + "/") || resolved == rootPath
    }

    private func extractLastMessage(at url: URL) -> LastMessage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let endOffset = try? handle.seekToEnd() else { return nil }
        let start = endOffset > UInt64(tailWindow) ? endOffset - UInt64(tailWindow) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }

        // If we started mid-line (start > 0), drop the partial first line.
        var lines = data.split(separator: 0x0A) // newline
        if start > 0 && !lines.isEmpty {
            lines.removeFirst()
        }

        for line in lines.reversed() {
            // Cheap prefilter: only `"role":"user"` or `"role":"assistant"` lines
            // can carry conversational text.
            let lineData = Data(line)
            let hasUser = lineData.range(of: Data("\"role\":\"user\"".utf8)) != nil
            let hasAssistant = lineData.range(of: Data("\"role\":\"assistant\"".utf8)) != nil
            guard hasUser || hasAssistant else { continue }

            if let parsed = parseLine(lineData) {
                return parsed
            }
        }
        return nil
    }

    private func parseLine(_ line: Data) -> LastMessage? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return nil
        }
        guard let type = obj["type"] as? String else { return nil }
        guard let message = obj["message"] as? [String: Any] else { return nil }

        // Store generously-capped text. The view layer applies `lineLimit(2)`
        // for collapsed display and `lineLimit(nil)` when peeked, so we must
        // NOT strip the body up front — doing that would leave peek nothing
        // extra to show.
        let cap = 4000
        switch type {
        case "user":
            // String content == user typed; array content == tool_result echo.
            if let text = message["content"] as? String {
                return LastMessage(role: .user, text: text.trimmed(to: cap))
            }
            return nil

        case "assistant":
            // content[] has text blocks and tool_use blocks; we want the LAST
            // text block in this assistant turn.
            guard let blocks = message["content"] as? [[String: Any]] else { return nil }
            for block in blocks.reversed() {
                if block["type"] as? String == "text",
                   let text = block["text"] as? String,
                   !text.isEmpty {
                    return LastMessage(role: .assistant, text: text.trimmed(to: cap))
                }
            }
            return nil

        default:
            return nil
        }
    }
}

private extension String {
    /// Truncate to `max` chars, collapse whitespace, append … if cut.
    func trimmed(to max: Int) -> String {
        let collapsed = self.split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if collapsed.count <= max { return collapsed }
        let idx = collapsed.index(collapsed.startIndex, offsetBy: max)
        return collapsed[..<idx].trimmingCharacters(in: .whitespaces) + "…"
    }
}
