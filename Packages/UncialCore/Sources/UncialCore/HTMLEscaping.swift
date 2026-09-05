import Foundation

enum HTMLEscaping {
    static func escape(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            default: output.append(character)
            }
        }
        return output
    }

    /// Decodes the entities cmark emits (`&amp; &lt; &gt; &quot; &#39;`) plus numeric references.
    static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&" {
                let window = text[index...].prefix(12)
                if let semicolon = window.firstIndex(of: ";"),
                   let decoded = decode(entity: text[text.index(after: index)..<semicolon]) {
                    output.append(decoded)
                    index = text.index(after: semicolon)
                    continue
                }
            }
            output.append(text[index])
            index = text.index(after: index)
        }
        return output
    }

    private static func decode(entity: Substring) -> Character? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default:
            guard entity.hasPrefix("#") else { return nil }
            let number = entity.dropFirst()
            let value: UInt32?
            if number.hasPrefix("x") || number.hasPrefix("X") {
                value = UInt32(number.dropFirst(), radix: 16)
            } else {
                value = UInt32(number)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return Character(scalar)
        }
    }
}
