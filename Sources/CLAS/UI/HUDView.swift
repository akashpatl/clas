import SwiftUI

struct HUDView: View {
    let store: SessionStore
    let attention: AttentionTracker
    let onSelect: (Session) -> Void

    /// Index into `sortedSessions`. Driven by both arrow keys AND mouse hover
    /// so that whatever is "highlighted" is always the same row regardless of
    /// which input mode the user used last.
    @State private var selectedIndex: Int = 0
    @FocusState private var rootFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.3)
            content
        }
        .frame(width: 640)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        // .focusable + @FocusState pulls the SwiftUI focus ring onto the
        // root container, which is what `.onKeyPress` actually listens on.
        // Without this, key events fall through to whatever child view
        // happened to grab focus (typically the first Button), which
        // means ↩ activates that button instead of firing our handler.
        .focusable()
        .focusEffectDisabled()
        .focused($rootFocused)
        .onAppear {
            let rows = sortedSessions
            selectedIndex = rows.firstIndex(where: { attention.needsAttention($0) }) ?? 0
            // Defer one runloop turn so the panel is fully key before we
            // try to take SwiftUI focus.
            DispatchQueue.main.async { rootFocused = true }
        }
        .onKeyPress(.upArrow) {
            move(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            move(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            activateCurrent()
            return .handled
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Claude sessions")
                .font(.title3.weight(.semibold))
            Spacer()
            let attCount = attention.count(in: store.sessions)
            if attCount > 0 {
                Label("\(attCount) need you", systemImage: "exclamationmark.bubble.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.15), in: Capsule())
            }
            keyHint("↑↓")
            keyHint("↩")
            keyHint("⎋")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func keyHint(_ symbol: String) -> some View {
        Text(symbol)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var content: some View {
        if store.sessions.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text("No active sessions")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            let rows = sortedSessions
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, session in
                        HUDRow(
                            session: session,
                            isSelected: index == selectedIndex,
                            onHover: { selectedIndex = index },
                            onClick: { onSelect(session) }
                        )
                        if index < rows.count - 1 {
                            Divider().opacity(0.2)
                        }
                    }
                }
            }
            .frame(maxHeight: 460)
        }
    }

    /// Sort: needs-attention first, then busy, then idle.
    /// Within a group, most-recently-updated first.
    private var sortedSessions: [Session] {
        let priority: (Session) -> Int = { s in
            if attention.needsAttention(s) { return 0 }
            switch s.status {
            case .busy:    return 1
            case .waiting: return 2 // formal waiting that's been dismissed
            case .idle:    return 3
            case .unknown: return 4
            }
        }
        return store.sessions.sorted { lhs, rhs in
            if priority(lhs) != priority(rhs) { return priority(lhs) < priority(rhs) }
            return (lhs.updatedAt ?? 0) > (rhs.updatedAt ?? 0)
        }
    }

    private func move(by delta: Int) {
        let rows = sortedSessions
        guard !rows.isEmpty else { return }
        selectedIndex = (selectedIndex + delta).clamped(to: 0...(rows.count - 1))
    }

    private func activateCurrent() {
        let rows = sortedSessions
        guard rows.indices.contains(selectedIndex) else { return }
        onSelect(rows[selectedIndex])
    }
}

private struct HUDRow: View {
    let session: Session
    let isSelected: Bool
    let onHover: () -> Void
    let onClick: () -> Void

    var body: some View {
        // NOT a Button: SwiftUI Buttons compete for focus and intercept
        // Return key presses, which would steal ↩ from the HUD's global
        // key handler. A tap-gesture-driven row is unfocusable so the
        // root HUD view keeps focus and ↩/↑/↓ all flow there.
        HStack(alignment: .top, spacing: 12) {
            statusIndicator
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(session.cwd)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                previewLine
                if let waitingFor = session.waitingFor, !waitingFor.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass")
                            .font(.caption2)
                        Text(waitingFor)
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                // Color.primary adapts under .ultraThinMaterial so hover/keyboard
                // selection reads in both light and dark mode menu bars.
                Color.primary.opacity(isSelected ? 0.08 : 0)
                if isSelected {
                    Rectangle()
                        .fill(.orange)
                        .frame(width: 3)
                }
            }
        }
        .onTapGesture { onClick() }
        .onHover { hovering in if hovering { onHover() } }
    }

    @ViewBuilder
    private var previewLine: some View {
        if let msg = session.lastMessage {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(msg.role == .user ? "You" : "Claude")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(msg.role == .user ? .blue : .purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        (msg.role == .user ? Color.blue : Color.purple).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                Text(msg.text)
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(2)
            }
        } else {
            Text("No messages yet")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 24, height: 24)
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
        .padding(.top, 2)
    }

    private var color: Color {
        switch session.status {
        case .waiting: .orange
        case .busy:    .blue
        case .idle:    .secondary
        case .unknown: .gray
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
