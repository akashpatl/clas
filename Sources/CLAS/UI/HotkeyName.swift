import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Default: ⌥Space (option-space). User-rebindable via the recorder.
    /// Avoids ⌘Space (Spotlight) and ⌘⇧Space (input source / emoji picker).
    static let toggleHUD = Self(
        "toggleHUD",
        default: .init(.space, modifiers: .option)
    )
}
