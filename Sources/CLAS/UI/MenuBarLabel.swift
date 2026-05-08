import SwiftUI

/// Menu-bar item appearance.
///
/// Two visuals from one bit of state:
///   - **Hollow `circle.dotted`** + no count when no sessions need you
///   - **Solid `circle.fill`** + count when one or more do
///
/// Color/symbol-effect animations are unreliable inside `MenuBarExtra`
/// labels on macOS 26; shape change is reliable. We rely on shape, not
/// color, as the load-bearing signal — `circle.dotted` rendered at
/// `.semibold` weight has decent contrast on both light and dark menu bars.
struct MenuBarLabel: View {
    let store: SessionStore
    let attention: AttentionTracker

    var body: some View {
        let count = attention.count(in: store.sessions)
        let needsAttention = count > 0
        HStack(spacing: 4) {
            Image(systemName: needsAttention ? "circle.fill" : "circle.dotted")
                .fontWeight(.semibold)
                .foregroundStyle(needsAttention ? Color.orange : Color.primary)
            if needsAttention {
                Text("\(count)")
            }
        }
    }
}
