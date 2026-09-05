public enum QuickLookExtensionState: Equatable, Sendable {
    case enabled, disabled, unregistered, unknown
}

/// Interprets `pluginkit -m -i <identifier>` output. Each registered copy is one line,
/// prefixed with the user election: `+` use, `-` ignore, ` ` default, `!` debugger, `=` superseded, `?` unknown.
public enum QuickLookElection {
    public static func parse(_ output: String) -> QuickLookExtensionState {
        guard let line = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).first,
              let prefix = line.first else { return .unregistered }
        switch prefix {
        case "-": return .disabled
        case "+", " ", "!", "=": return .enabled
        default: return .unknown
        }
    }
}
