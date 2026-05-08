import Foundation

/// Mirror of `~/.claude/sessions/{pid}.json`, written by the Claude Code CLI.
///
/// Schema is undocumented and may drift between CLI releases — every
/// secondary field is optional so a partial decode degrades the row
/// instead of dropping the session entirely.
struct Session: Codable, Identifiable, Equatable {
    let pid: Int
    let sessionId: String
    let cwd: String
    /// Default `.idle` for older / non-interactive sessions (e.g. `sdk-cli`)
    /// that don't write the field at all.
    let status: Status
    let waitingFor: String?
    let name: String?
    let startedAt: Int?
    let updatedAt: Int?
    let version: String?
    let kind: String?

    /// Enriched at scan time from the JSONL transcript. Excluded from Codable.
    /// Most recent conversational message — could be from the user or claude.
    var lastMessage: LastMessage?

    var id: Int { pid }

    private enum CodingKeys: String, CodingKey {
        case pid, sessionId, cwd, status, waitingFor, name
        case startedAt, updatedAt, version, kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pid = try c.decode(Int.self, forKey: .pid)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        cwd = try c.decode(String.self, forKey: .cwd)
        status = (try c.decodeIfPresent(Status.self, forKey: .status)) ?? .idle
        waitingFor = try c.decodeIfPresent(String.self, forKey: .waitingFor)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        startedAt = try c.decodeIfPresent(Int.self, forKey: .startedAt)
        updatedAt = try c.decodeIfPresent(Int.self, forKey: .updatedAt)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
    }

    enum Status: String, Codable {
        case busy
        case idle
        case waiting
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    var displayTitle: String {
        if let name, !name.isEmpty { return name }
        return (cwd as NSString).lastPathComponent
    }

    var startedAtDate: Date? {
        startedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    var updatedAtDate: Date? {
        updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }
}
