import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    let store: SessionStore
    let attention: AttentionTracker
    let onSelect: (Session) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Claude sessions")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if store.sessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "moon.zzz")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No active sessions")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(sortedSessions) { session in
                    SessionRow(
                        session: session,
                        needsAttention: attention.needsAttention(session),
                        onClick: { onSelect(session) }
                    )
                    Divider()
                }
            }

            Divider()

            HStack(spacing: 8) {
                Text("HUD hotkey")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                KeyboardShortcuts.Recorder(for: .toggleHUD)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 380)
    }

    /// MRU sort by user activation — same rule as the HUD.
    private var sortedSessions: [Session] {
        store.sessions.sorted { lhs, rhs in
            let lActive = attention.lastActivation(of: lhs.sessionId)
            let rActive = attention.lastActivation(of: rhs.sessionId)
            if lActive != rActive { return lActive > rActive }
            return (lhs.updatedAt ?? 0) > (rhs.updatedAt ?? 0)
        }
    }
}

struct SessionRow: View {
    let session: Session
    let needsAttention: Bool
    let onClick: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if needsAttention {
                Rectangle()
                    .fill(.orange)
                    .frame(width: 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    statusDot
                    titleText
                    Spacer()
                }
                previewLine
                if let waitingFor = session.waitingFor, !waitingFor.isEmpty {
                    Text(waitingFor)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                if !session.isFocusable {
                    Text("Run /rename in claude to enable focus")
                        .font(.caption2.italic())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(session.isFocusable ? 1.0 : 0.55)
        .contentShape(Rectangle())
        .background(hovering && session.isFocusable ? Color.primary.opacity(0.06) : Color.clear)
        .onTapGesture { onClick() }
        .onHover { hovering = $0 }
        .help(session.isFocusable ? session.cwd : "\(session.cwd) — /rename to enable focus")
    }

    @ViewBuilder
    private var titleText: some View {
        // Italic for unfocusable (auto-derived from cwd) sessions to signal
        // "this isn't a real /rename name; you can't navigate to this".
        if session.isFocusable {
            Text(session.displayTitle)
                .font(.body)
                .lineLimit(1)
        } else {
            Text(session.displayTitle)
                .font(.body.italic())
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var previewLine: some View {
        if let msg = session.lastMessage {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(msg.role == .user ? "You" : "Claude")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(msg.role == .user ? .blue : .purple)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        (msg.role == .user ? Color.blue : Color.purple).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 3)
                    )
                Text(msg.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } else {
            Text("No messages yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        // Orange = your turn (waiting OR idle); blue = claude is working.
        // Grey only for unrecognised status.
        switch session.status {
        case .waiting, .idle: .orange
        case .busy:           .blue
        case .unknown:        .gray
        }
    }
}
