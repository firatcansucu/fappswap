/// Builds fragments of AppleScript source safely.
public enum AppleScript {
    /// Returns `value` as an AppleScript double-quoted string literal, quotes included.
    ///
    /// Everything interpolated into a script has to go through here. Bundle IDs reach
    /// `AppActivator` from `bindings.json`, a plain file that anything running as the
    /// user can edit, so a `"` in one would otherwise close the literal in
    /// `tell application id "..." to activate` and leave the rest to be parsed as
    /// statements. The picker only ever yields reverse-DNS identifiers; the file does
    /// not have to.
    ///
    /// Returning the surrounding quotes rather than just the escaped body is
    /// deliberate — a caller cannot then escape the contents and forget to quote them.
    public static func quoted(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "\\": escaped += #"\\"#
            case "\"": escaped += #"\""#
            // AppleScript string literals cannot span lines; these must become escapes.
            case "\n": escaped += #"\n"#
            case "\r": escaped += #"\r"#
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }
}
