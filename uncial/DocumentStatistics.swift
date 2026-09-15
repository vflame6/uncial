import Foundation

/// Line, word and character counts of a document, as the status bar shows them.
///
/// Lines are counted the way the gutter numbers them (line breaks plus one, so an empty document has
/// one line). Words are runs of letters, digits and combining marks; a single apostrophe, hyphen,
/// underscore, period, comma or colon between two such characters keeps the run going (`don't`,
/// `well-known`, `3,857`, `e.g.`), so Markdown markers such as `#`, `*` and `-` never count.
/// Chinese, Japanese and Korean characters count one word each. Characters are what a person would
/// count: grapheme clusters, spaces and line breaks included.
nonisolated struct DocumentStatistics: Equatable, Sendable {
    let lines: Int
    let words: Int
    let characters: Int

    init(lines: Int, words: Int, characters: Int) {
        self.lines = lines
        self.words = words
        self.characters = characters
    }

    init(text: String) {
        var lines = 1
        var words = 0
        var inWord = false
        var afterConnector = false
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            let isCR = scalar == "\r"
            if isCR || (scalar == "\n" && !previousWasCR) {
                lines += 1
            }
            previousWasCR = isCR

            switch Self.classify(scalar) {
            case .cjk:
                words += 1
                inWord = false
                afterConnector = false
            case .mark:
                // Continues a word, never starts one (a variation selector after an emoji is a mark too).
                afterConnector = false
            case .wordCharacter:
                if !inWord {
                    words += 1
                    inWord = true
                }
                afterConnector = false
            case .connector where inWord && !afterConnector:
                afterConnector = true
            case .connector, .other:
                inWord = false
                afterConnector = false
            }
        }
        self.lines = lines
        self.words = words
        characters = text.count
    }

    /// "1 line", "3,857 characters".
    static func phrase(_ count: Int, _ noun: String, locale: Locale = .autoupdatingCurrent) -> String {
        "\(count.formatted(.number.locale(locale))) \(count == 1 ? noun : noun + "s")"
    }

    // MARK: - Classification

    private enum Kind {
        case cjk, mark, wordCharacter, connector, other
    }

    /// ASCII is decided with comparisons; everything else asks the Unicode properties.
    private static func classify(_ scalar: Unicode.Scalar) -> Kind {
        if scalar.isASCII {
            return switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9": .wordCharacter
            case "'", "-", "_", ".", ",", ":": .connector
            default: .other
            }
        }
        if scalar == "\u{2019}" { return .connector }
        if isCJK(scalar) { return .cjk }
        return switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            .wordCharacter
        case .nonspacingMark, .spacingMark, .enclosingMark:
            .mark
        default:
            .other
        }
    }

    /// Han ideographs, kana and Hangul: scripts without spaces between words.
    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.isIdeographic { return true }
        return switch scalar.value {
        case 0x3040...0x30FF, // Hiragana, Katakana
             0x31F0...0x31FF, // Katakana phonetic extensions
             0xFF66...0xFF9F, // halfwidth Katakana
             0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F, 0xAC00...0xD7FF: // Hangul
            true
        default:
            false
        }
    }
}
