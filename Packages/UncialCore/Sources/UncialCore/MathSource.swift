import Foundation

/// The formulas of a Markdown source, taken out before cmark reads it and put back as written right
/// after (`restore(in:)`), so backslash escapes, `*` and `_` never reach the TeX of a `$…$` or
/// `$$…$$` that `MathRenderer` then draws. The rules are `MathRenderer`'s: inline math stays on one
/// line, with no space inside the dollars, no word character, `$` or backslash before the opening
/// one and no digit or `$` after the closing one; a `$$…$$` block may run over lines up to a blank
/// one. Code spans and fenced code are left alone. Each formula becomes an alphanumeric placeholder
/// on the same lines (a block's later lines keep their blockquote markers and indentation), so
/// cmark sees the same blocks and source lines as before.
struct MathSource {
    /// The source with every formula replaced by its placeholder.
    let masked: String
    private let formulas: [Formula]
    private let token: String

    private struct Formula {
        /// The dollars and the TeX, a block's later lines without their container prefix.
        let math: String
        /// The source as written, for a placeholder that ended up in code after all (an indented code block).
        let source: String
    }

    private typealias Line = [Unicode.Scalar]

    init(_ markdown: String) {
        var token = "uncialmath"
        while markdown.contains(token) { token += "x" }
        self.token = token
        guard markdown.contains("$") else {
            masked = markdown
            formulas = []
            return
        }
        let lines: [Line] = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { Array($0.unicodeScalars) }
        let continuation = Array("\(token)cz".unicodeScalars)
        var formulas: [Formula] = []
        var output: [Line] = []
        var fence: (marker: Unicode.Scalar, count: Int)?
        var index = 0
        while index < lines.count {
            if let open = fence {
                if Self.closesFence(lines[index], open) { fence = nil }
                output.append(lines[index])
                index += 1
                continue
            }
            if let opening = Self.opensFence(lines[index]) {
                fence = opening
                output.append(lines[index])
                index += 1
                continue
            }
            var line = lines[index]
            var built: Line = []
            var column = 0
            while column < line.count {
                let scalar = line[column]
                if scalar == "\\" {
                    built += line[column..<min(column + 2, line.count)]
                    column += 2
                } else if scalar == "`" {
                    let run = Self.run(of: "`", in: line, at: column)
                    let end = Self.closingRun(in: line, from: column + run, length: run).map { $0 + run } ?? column + run
                    built += line[column..<end]
                    column = end
                } else if scalar == "$", column + 1 < line.count, line[column + 1] == "$" {
                    let before: Unicode.Scalar? = column > 0 ? line[column - 1] : nil
                    guard before != "\\", let block = Self.block(in: lines, line: index, text: line, open: column) else {
                        built += line[column...(column + 1)]
                        column += 2
                        continue
                    }
                    formulas.append(Formula(math: "$$" + block.tex + "$$", source: block.source))
                    built += Array("\(token)\(formulas.count - 1)z".unicodeScalars)
                    if block.line == index {
                        column = block.column
                    } else {
                        output.append(built)
                        for middle in (index + 1)..<block.line {
                            output.append(Array(lines[middle][..<block.prefixes[middle - index - 1]]) + continuation)
                        }
                        index = block.line
                        line = lines[index]
                        built = Array(line[..<block.prefixes[block.prefixes.count - 1]]) + continuation
                        column = block.column
                    }
                } else if scalar == "$", !Self.blocksOpening(column > 0 ? line[column - 1] : nil),
                          let close = Self.inlineClose(in: line, open: column) {
                    let math = String(String.UnicodeScalarView(line[column...close]))
                    formulas.append(Formula(math: math, source: math))
                    built += Array("\(token)\(formulas.count - 1)z".unicodeScalars)
                    column = close + 1
                } else {
                    built.append(scalar)
                    column += 1
                }
            }
            output.append(built)
            index += 1
        }
        masked = output.map { String(String.UnicodeScalarView($0)) }.joined(separator: "\n")
        self.formulas = formulas
    }

    /// `html` (cmark's output for `masked`) with every placeholder turned back into its formula:
    /// the formula's text for `MathRenderer`, or the source as written where it landed in code.
    func restore(in html: String) -> String {
        guard !formulas.isEmpty else { return html }
        let name = NSRegularExpression.escapedPattern(for: token)
        let placeholder = try! NSRegularExpression(pattern: "\(name)(\\d+)z(?:\\n[ \\t>]*\(name)cz)*")
        let source = html as NSString
        let code = Self.protected.matches(in: html, range: NSRange(location: 0, length: source.length)).map(\.range)
        var output = ""
        var cursor = 0
        for match in placeholder.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            guard let number = Int(source.substring(with: match.range(at: 1))), number < formulas.count else { continue }
            let inCode = code.contains { NSLocationInRange(match.range.location, $0) }
            output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += HTMLEscaping.escape(inCode ? formulas[number].source : formulas[number].math)
            cursor = NSMaxRange(match.range)
        }
        output += source.substring(from: cursor)
        return output
    }

    private static let protected = try! NSRegularExpression(pattern: #"<pre\b[^>]*>[\s\S]*?</pre>|<code\b[^>]*>[\s\S]*?</code>"#)

    /// A `$$` block from `open` in `text` (line `line` of `lines`): its closing `$$` on the same line,
    /// or on a later line before any blank line or fence. `column` is just past the closing `$$` on
    /// line `line`; `prefixes` are the container prefix lengths of the lines after the first.
    private static func block(in lines: [Line], line: Int, text: Line, open: Int) -> (line: Int, column: Int, tex: String, source: String, prefixes: [Int])? {
        let start = open + 2
        if let close = doubleDollar(in: text, from: start + 1), !text[start..<close].contains("`") {
            return (line, close + 2, string(text[start..<close]), string(text[open..<(close + 2)]), [])
        }
        guard !text[start...].contains("`") else { return nil }
        let depth = quoteDepth(of: lines[line])
        var tex = [string(text[start...])]
        var source = [string(text[open...])]
        var prefixes: [Int] = []
        for next in (line + 1)..<lines.count {
            let current = lines[next]
            let prefix = containerPrefix(of: current, quotes: depth)
            prefixes.append(prefix)
            let content = current[prefix...]
            guard !content.allSatisfy(\.properties.isWhitespace), opensFence(current) == nil else { return nil }
            if let close = doubleDollar(in: current, from: prefix) {
                guard !current[prefix..<close].contains("`") else { return nil }
                tex.append(string(current[prefix..<close]))
                source.append(string(current[..<(close + 2)]))
                return (next, close + 2, tex.joined(separator: "\n"), source.joined(separator: "\n"), prefixes)
            }
            guard !content.contains("`") else { return nil }
            tex.append(string(content))
            source.append(string(current))
        }
        return nil
    }

    /// The closing `$` of inline math opening at `open`, per `MathRenderer`'s rules.
    private static func inlineClose(in line: Line, open: Int) -> Int? {
        let first = open + 1
        guard first < line.count, !line[first].properties.isWhitespace, line[first] != "$",
              let close = line[first...].firstIndex(of: "$") else { return nil }
        let last = line[close - 1]
        guard !last.properties.isWhitespace, last != "\\", !line[first..<close].contains("`") else { return nil }
        if close + 1 < line.count, line[close + 1] == "$" || line[close + 1].properties.numericType != nil { return nil }
        return close
    }

    /// No inline math opens after a word character, a `$` or a backslash.
    private static func blocksOpening(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return scalar == "$" || scalar == "\\" || scalar == "_" || scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }

    private static func doubleDollar(in line: Line, from start: Int) -> Int? {
        var index = start
        while index + 1 < line.count {
            if line[index] == "$", line[index + 1] == "$" { return index }
            index += 1
        }
        return nil
    }

    private static func run(of scalar: Unicode.Scalar, in line: Line, at start: Int) -> Int {
        var end = start
        while end < line.count, line[end] == scalar { end += 1 }
        return end - start
    }

    /// Where a backtick run of exactly `length` starts at or after `start`, closing a code span.
    private static func closingRun(in line: Line, from start: Int, length: Int) -> Int? {
        var index = start
        while index < line.count {
            if line[index] == "`" {
                let run = run(of: "`", in: line, at: index)
                if run == length { return index }
                index += run
            } else {
                index += 1
            }
        }
        return nil
    }

    /// Leading whitespace and up to `quotes` blockquote markers.
    private static func containerPrefix(of line: Line, quotes: Int) -> Int {
        var index = 0
        var seen = 0
        while index < line.count {
            if line[index] == " " || line[index] == "\t" {
                index += 1
            } else if line[index] == ">", seen < quotes {
                seen += 1
                index += 1
            } else {
                break
            }
        }
        return index
    }

    private static func quoteDepth(of line: Line) -> Int {
        line.prefix { $0 == " " || $0 == "\t" || $0 == ">" }.filter { $0 == ">" }.count
    }

    /// A fence line (leading whitespace and blockquote markers allowed): its marker and length. A
    /// backtick fence's info string has no backtick.
    private static func opensFence(_ line: Line) -> (marker: Unicode.Scalar, count: Int)? {
        let start = line.firstIndex { $0 != " " && $0 != "\t" && $0 != ">" } ?? line.count
        guard start < line.count, line[start] == "`" || line[start] == "~" else { return nil }
        let marker = line[start]
        let count = run(of: marker, in: line, at: start)
        guard count >= 3, marker == "~" || !line[(start + count)...].contains("`") else { return nil }
        return (marker, count)
    }

    private static func closesFence(_ line: Line, _ open: (marker: Unicode.Scalar, count: Int)) -> Bool {
        let start = line.firstIndex { $0 != " " && $0 != "\t" && $0 != ">" } ?? line.count
        guard start < line.count, line[start] == open.marker else { return false }
        let count = run(of: open.marker, in: line, at: start)
        return count >= open.count && line[(start + count)...].allSatisfy(\.properties.isWhitespace)
    }

    private static func string<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        String(String.UnicodeScalarView(scalars))
    }
}
