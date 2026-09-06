import Foundation

/// Turns a Swift string into a double-quoted JavaScript string literal for `evaluateJavaScript`.
nonisolated enum JavaScriptLiteral {
    static func string(_ value: String) -> String {
        var output = "\""
        output.reserveCapacity(value.utf8.count + 2)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\u{2028}": output += "\\u2028"
            case "\u{2029}": output += "\\u2029"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04x", scalar.value)
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        return output + "\""
    }
}
