/// Why a snippet or prefix was rejected. Carries its own user-facing text so the
/// dialogs never have to restate the rules.
public enum SnippetValidationError: Equatable, Sendable {
    case emptyTrigger
    case emptyReplacement
    case whitespaceInTrigger
    case triggerContainsPrefix(String)
    case duplicateTrigger(String)
    case collidingTrigger(existing: String)
    case prefixNotSingleCharacter
    case prefixNotPunctuation
    case prefixUsedInExistingTrigger(String)

    public var message: String {
        switch self {
        case .emptyTrigger:
            return "Enter a trigger, for example sig."
        case .emptyReplacement:
            return "Enter the text this snippet should expand to."
        case .whitespaceInTrigger:
            return "Triggers can't contain spaces."
        case .triggerContainsPrefix(let prefix):
            return "Triggers can't contain the prefix \(prefix)."
        case .duplicateTrigger(let trigger):
            return "\(trigger) is already used by another snippet."
        case .collidingTrigger(let existing):
            return "This overlaps with \(existing). Expansion fires on the last "
                + "character typed, so the shorter of two overlapping triggers "
                + "always wins and the longer one could never be typed."
        case .prefixNotSingleCharacter:
            return "The prefix must be exactly one character."
        case .prefixNotPunctuation:
            return "The prefix must not be a letter, a digit or a space — "
                + "pick something you never type, like § or :."
        case .prefixUsedInExistingTrigger(let trigger):
            return "The trigger \(trigger) contains that character, so it can't "
                + "also be the prefix."
        }
    }
}
