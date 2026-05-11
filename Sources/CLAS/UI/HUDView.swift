import SwiftUI

struct HUDView: View {
    let store: SessionStore
    let attention: AttentionTracker
    let onSelect: (Session) -> Void

    /// Index into `sortedSessions`. Driven by both arrow keys AND mouse hover
    /// so that whatever is "highlighted" is always the same row regardless of
    /// which input mode the user used last.
    @State private var selectedIndex: Int = 0
    /// SessionId of the currently peeked (right-arrow expanded) row, if any.
    /// Held by sessionId so re-sorting doesn't drift the peek to a wrong row.
    @State private var peekedSessionId: String?
    /// Typeahead query. We do NOT use a TextField — printable characters
    /// land here via `.onKeyPress`, backspace pops, escape clears. This
    /// avoids a focus tug-of-war between the field and the arrow-key
    /// navigation we already have on the root view.
    @State private var searchText: String = ""
    @FocusState private var rootFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            Divider().opacity(0.3)
            content
        }
        .frame(width: 640)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        // Force dark appearance so the HUD reads on any wallpaper (Raycast
        // and Spotlight do the same). `.regularMaterial` is meaningfully
        // more opaque than `.ultraThinMaterial`, which fixed contrast over
        // bright/white desktops where the latter washed out.
        .environment(\.colorScheme, .dark)
        // .focusable + @FocusState pulls the SwiftUI focus ring onto the
        // root container, which is what `.onKeyPress` actually listens on.
        // Without this, key events fall through to whatever child view
        // happened to grab focus (typically the first Button), which
        // means ↩ activates that button instead of firing our handler.
        .focusable()
        .focusEffectDisabled()
        .focused($rootFocused)
        .onAppear {
            let rows = filteredSessions
            selectedIndex = rows.firstIndex(where: { attention.needsAttention($0) }) ?? 0
            // Defer one runloop turn so the panel is fully key before we
            // try to take SwiftUI focus.
            DispatchQueue.main.async { rootFocused = true }
        }
        // Single key-press handler. Phases include `.repeat` so held arrow
        // keys keep firing without macOS beeping.
        //
        // Quirk: on macOS 26 SwiftUI, Backspace and Escape arrive as
        // `KeyEquivalent(character: "\u{7F}")` / `"\u{1B}"` — NOT as the
        // named constants `.delete` / `.escape`. The named constants
        // never match. Match those two by character; arrows + Return
        // work fine via the named key matching.
        .onKeyPress(phases: [.down, .repeat]) { keyPress in
            switch keyPress.characters {
            case "\u{7F}": // Backspace
                guard !searchText.isEmpty else { return .ignored }
                searchText.removeLast()
                return .handled
            case "\u{1B}": // Escape — clear filter first; else let panel dismiss.
                if !searchText.isEmpty {
                    searchText = ""
                    return .handled
                }
                return .ignored
            default:
                break
            }
            switch keyPress.key {
            case .upArrow:
                move(by: -1)
                return .handled
            case .downArrow:
                move(by: 1)
                return .handled
            case .return:
                activateCurrent()
                return .handled
            case .rightArrow:
                togglePeek()
                return .handled
            case .leftArrow:
                peekedSessionId = nil
                return .handled
            default:
                guard let ch = keyPress.characters.first,
                      ch.isLetter || ch.isNumber || ch == " " || ch == "-" || ch == "_" || ch == "/" || ch == "." else {
                    return .ignored
                }
                searchText.append(keyPress.characters)
                return .handled
            }
        }
        .onChange(of: searchText) { _, _ in
            // Filter changed — keep selectedIndex valid, and drop any
            // peek (the peeked row may have been filtered out anyway).
            peekedSessionId = nil
            let rows = filteredSessions
            if !rows.indices.contains(selectedIndex) {
                selectedIndex = rows.isEmpty ? 0 : 0
            }
        }
    }

    /// Raycast-style top-of-chrome search. No TextField — typed
    /// characters land here via the root view's `.onKeyPress`
    /// handlers, which also keeps our arrow-key bindings intact.
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.tertiary)
            if searchText.isEmpty {
                Text("Search Claude sessions")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            } else {
                Text(searchText)
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
            // Subtle total-session count. Stays put regardless of filter
            // so the user always sees "how many real sessions exist".
            Text("\(store.sessions.count) \(store.sessions.count == 1 ? "session" : "sessions")")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var content: some View {
        // Fixed-height content area. Without this, the three branches
        // (empty store / no search matches / list) each have their own
        // intrinsic height and the panel resizes around them as the
        // user types and deletes. Locking the height keeps the panel
        // window stable; SwiftUI just swaps what's drawn inside.
        Group {
            if store.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No active sessions")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredSessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No sessions match “\(searchText)”")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let rows = filteredSessions
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, session in
                                HUDRow(
                                    session: session,
                                    isSelected: index == selectedIndex,
                                    isPeeked: session.sessionId == peekedSessionId,
                                    onHover: { selectedIndex = index },
                                    onClick: { onSelect(session) }
                                )
                                .id(session.id)
                                if index < rows.count - 1 {
                                    Divider().opacity(0.2)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        // Peek deliberately NOT cleared here — see togglePeek
                        // and the layout-feedback note in earlier commits.
                        guard rows.indices.contains(newIndex) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(rows[newIndex].id)
                        }
                    }
                }
            }
        }
        .frame(height: 460)
    }

    /// Sort + filter — what the rows ForEach actually iterates over.
    /// `sortedSessions` is the priority/recency order; `filteredSessions`
    /// applies the typeahead query on top of that. Sort first so search
    /// matches stay in the same intuitive order users learned.
    private var filteredSessions: [Session] {
        let sorted = sortedSessions
        guard !searchText.isEmpty else { return sorted }
        let q = searchText.lowercased()
        return sorted.filter { s in
            if s.displayTitle.lowercased().contains(q) { return true }
            if s.cwd.lowercased().contains(q) { return true }
            if let text = s.lastMessage?.text.lowercased(), text.contains(q) { return true }
            return false
        }
    }

    /// MRU sort by user activation: whichever session the user pressed
    /// (↩ / click) most recently floats to the top. Sessions never
    /// activated fall back to claude-updated recency as a stable
    /// tiebreaker so the order doesn't shuffle on app launch.
    private var sortedSessions: [Session] {
        store.sessions.sorted { lhs, rhs in
            let lActive = attention.lastActivation(of: lhs.sessionId)
            let rActive = attention.lastActivation(of: rhs.sessionId)
            if lActive != rActive { return lActive > rActive }
            return (lhs.updatedAt ?? 0) > (rhs.updatedAt ?? 0)
        }
    }

    private func move(by delta: Int) {
        let rows = filteredSessions
        guard !rows.isEmpty else { return }
        selectedIndex = (selectedIndex + delta).clamped(to: 0...(rows.count - 1))
    }

    private func activateCurrent() {
        let rows = filteredSessions
        guard rows.indices.contains(selectedIndex) else { return }
        onSelect(rows[selectedIndex])
    }

    private func togglePeek() {
        let rows = filteredSessions
        guard rows.indices.contains(selectedIndex) else { return }
        let id = rows[selectedIndex].sessionId
        peekedSessionId = (peekedSessionId == id) ? nil : id
    }
}

private struct HUDRow: View {
    let session: Session
    let isSelected: Bool
    /// → on the selected row toggles this. When true: drop the preview
    /// truncation, show a relative-time stamp near the title. Stays
    /// boring on purpose — peek is for "should I jump in?", not for
    /// reading the full transcript.
    let isPeeked: Bool
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
                    titleText
                    Text(session.cwd)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isPeeked, let relative = relativeUpdatedLabel {
                        Text(relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
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
                if !session.isFocusable {
                    Text("Run /rename in claude to enable focus")
                        .font(.caption2.italic())
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(session.isFocusable ? 1.0 : 0.55)
        .contentShape(Rectangle())
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                // Color.primary adapts under .ultraThinMaterial so hover/keyboard
                // selection reads in both light and dark mode menu bars.
                Color.primary.opacity(isSelected ? 0.08 : 0)
                // Soft purple tint signals "this row is peeked" — visual
                // confirmation that → took effect, even when the message
                // text didn't grow much.
                Color.purple.opacity(isPeeked ? 0.10 : 0)
                if isSelected {
                    Rectangle()
                        .fill(.orange)
                        .frame(width: 3)
                }
            }
        }
        .onTapGesture { onClick() }
        .onHover { hovering in if hovering { onHover() } }
        // Smooth the expand/collapse so the row doesn't snap when peeked.
        .animation(.easeInOut(duration: 0.18), value: isPeeked)
    }

    @ViewBuilder
    private var titleText: some View {
        // Italic for unfocusable (auto-derived from cwd) sessions to signal
        // "this isn't a real /rename name; you can't navigate to this".
        if session.isFocusable {
            Text(session.displayTitle)
                .font(.body.weight(.medium))
                .lineLimit(1)
        } else {
            Text(session.displayTitle)
                .font(.body.weight(.medium).italic())
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var previewLine: some View {
        if let msg = session.lastMessage {
            // Switched from HStack(.firstTextBaseline) to VStack so the
            // message text gets the full row width to wrap into. In an
            // HStack, even with .lineLimit(nil) + .fixedSize, SwiftUI
            // sometimes pins the text to its initial 2-line height when
            // the sibling badge is short. VStack sidesteps the entire
            // baseline-alignment puzzle.
            VStack(alignment: .leading, spacing: 4) {
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
                    .lineLimit(isPeeked ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("No messages yet")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .italic()
        }
    }

    /// "Nm ago" / "just now" — used in peek mode next to the title.
    /// nil when we have no `updatedAt`.
    private var relativeUpdatedLabel: String? {
        guard let date = session.updatedAtDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
        // Orange unifies "claude isn't actively working" — waiting (formal)
        // and idle (just stopped). Blue is the only "claude is doing things"
        // state. Cleaner binary: orange = your turn, blue = claude's turn.
        switch session.status {
        case .waiting, .idle: .orange
        case .busy:           .blue
        case .unknown:        .gray
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
