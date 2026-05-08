import Foundation

extension String {
    /// Escapes a Swift string for safe insertion into an AppleScript string literal.
    ///
    /// Why all four substitutions:
    ///   - `\\` and `"` are the standard AppleScript string escapes
    ///   - `\n` and `\r` are NOT escapable inside an AppleScript literal at all;
    ///     a raw newline ends the statement. A `cwd` or session name containing
    ///     a newline could otherwise break out of the surrounding `tell`/`display
    ///     notification` and inject arbitrary AppleScript. Replace with a space.
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
