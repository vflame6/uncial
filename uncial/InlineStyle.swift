import AppKit
import UncialCore

extension NSAttributedString.Key {
    /// Paragraph decoration drawn by `InlineLayoutManager`: "code", "quote:N", "rule" or "heading"
    /// (a divider under an h1 or h2, as the page draws).
    static let blockDecoration = NSAttributedString.Key("uncialBlockDecoration")
    /// A task box `[ ]`/`[x]` drawn by `InlineLayoutManager`: "unchecked" or "checked".
    static let taskBox = NSAttributedString.Key("uncialTaskBox")
    /// An `InlineImage` drawn by `InlineLayoutManager` in the paragraph's reserved spacing.
    static let inlineImage = NSAttributedString.Key("uncialInlineImage")
    /// A `MathPicture` on the one character that stands for a formula, drawn by `InlineLayoutManager`.
    static let mathPicture = NSAttributedString.Key("uncialMathPicture")
    /// A `CalloutTitle` on a callout's first line: `InlineLayoutManager` draws the icon before it.
    static let calloutTitle = NSAttributedString.Key("uncialCalloutTitle")
}

/// A callout's first line: the type it is drawn as, its quote depth (the icon sits at that
/// level's text indent) and, when the line names no title, the title to draw after the icon.
final class CalloutTitle: NSObject {
    let type: String
    let depth: Int
    let defaultTitle: String?

    init(type: String, depth: Int, defaultTitle: String?) {
        self.type = type
        self.depth = depth
        self.defaultTitle = defaultTitle
    }
}

/// A loaded image and the size it is drawn at under its paragraph.
final class InlineImage: NSObject {
    let image: NSImage
    let size: NSSize

    init(image: NSImage, size: NSSize) {
        self.image = image
        self.size = size
    }
}

/// A formula drawn in place of its TeX: the bitmap, the size it is drawn at in points, and the
/// distance from its top to the text baseline.
final class MathPicture: NSObject {
    let image: NSImage
    let size: NSSize
    let baseline: CGFloat

    init(image: NSImage, size: NSSize, baseline: CGFloat) {
        self.image = image
        self.size = size
        self.baseline = baseline
    }

    /// Scaled down, never up, to fit `width`.
    func fitted(to width: CGFloat) -> MathPicture {
        guard size.width > width, size.width > 0 else { return self }
        let scale = width / size.width
        return MathPicture(image: image, size: NSSize(width: floor(size.width * scale), height: floor(size.height * scale)), baseline: (baseline * scale).rounded())
    }
}

/// Attributes for the inline presentation. Outside the revealed lines the text takes the rendered
/// page's look (`EditorStyle.renderedAttributes`): the theme's body font and line height, headings
/// at the page's sizes with a divider under h1 and h2, code in the mono font at 85% on a background,
/// list items hanging by their marker's width, quotes indented behind a border, links in the accent
/// color, markers muted (and hidden by `ThemedTextView`); callouts (`Callouts`) as a tinted box in the
/// role color with their icon and title, the decoration a stack per quote level (`callout:<type>` or
/// `quote`, `quote:N` for plain quotes). The revealed lines, the caret's paragraph
/// or its fenced block, keep the source look: SF Mono and the source presentation's coloring, no
/// decorations, no pictures. Attribute-only, so undo never sees it.
struct InlineStyle {
    static let quoteIndent: CGFloat = 16
    /// A callout's icon, in points at the system size, and the room between it and the title.
    static let calloutIconSize: CGFloat = 18
    static let calloutIconGap: CGFloat = 6
    /// Room kept above a callout's title and below its last line.
    static let calloutPadding: CGFloat = 6
    static let codeIndent: CGFloat = 12
    /// Room a task box gets on its line: the square plus a little air on each side.
    static let taskBoxWidth: CGFloat = 18
    static let maximumImageHeight: CGFloat = 480
    static let maximumDiagramHeight: CGFloat = 800
    /// Room kept between a paragraph's last line and the image drawn under it.
    static let imageGap: CGFloat = 8
    /// Room kept between a formula's picture and the lines around it.
    static let mathGap: CGFloat = 2

    /// What `apply` drew as pictures: the image tokens' locations, the opening fences of diagrams,
    /// and for formulas the token or block start → the character that stands for the picture (the
    /// opening dollar, or a block's closing fence start); plus every fenced block that can be a
    /// picture, drawn or not.
    struct Resolved: Equatable {
        var images: Set<Int> = []
        var diagrams: Set<Int> = []
        var math: [Int: Int] = [:]
        var pictureBlocks: [NSRange] = []
    }

    /// A fenced block: ``` or ~~~ with its info string, or a `$$` math block (info `math`). `range`
    /// spans both fence lines (an unclosed one ends at its last content line), `lines` is the
    /// content, `closing` the closing fence line's start.
    struct FencedBlock: Equatable {
        let range: NSRange
        let info: String
        let lines: [String]
        let closing: Int?

        var isDiagram: Bool { firstWord == "mermaid" && !lines.isEmpty }
        var isMath: Bool { firstWord == "math" && !lines.isEmpty }
        private var firstWord: Substring? { info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first }
    }

    /// A mermaid fence: `range` spans both fence lines (an unclosed one ends at its last code
    /// line), `source` is the diagram text as `MermaidRenderer.key(for:)` normalizes it.
    struct DiagramBlock: Equatable {
        let range: NSRange
        let source: String
    }

    let style: EditorStyle
    /// The advance of one character of the mono font.
    let characterWidth: CGFloat

    var codeBackground: NSColor { style.foreground.withAlphaComponent(0.06) }

    init(style: EditorStyle) {
        self.style = style
        characterWidth = Self.advance(of: "0", in: style.regular)
    }

    /// The advance of one character in a font, straight from CoreText.
    static func advance(of character: Character, in font: NSFont) -> CGFloat {
        var characters = Array(String(character).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font as CTFont, &characters, &glyphs, characters.count) else {
            return font.maximumAdvancement.width
        }
        var advances = [CGSize](repeating: .zero, count: glyphs.count)
        return CTFontGetAdvancesForGlyphs(font as CTFont, .horizontal, &glyphs, &advances, glyphs.count)
    }

    /// The width `text` takes laid out in `font`: what indents and table padding are measured in.
    static func width(of text: String, in font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    func headingFont(level: Int) -> NSFont {
        style.heading(level: level)
    }

    /// `storage` must already carry the base attributes for its whole text. `images` loads an
    /// image token's destination, `diagrams` a mermaid fence's picture and `math` a formula's (TeX,
    /// display); nil keeps any of them as source, and nothing inside `revealed` is asked for.
    /// `textWidth` is the room for text, which bounds the drawn sizes. Returns what got a picture.
    @discardableResult
    func apply(_ tokens: [MarkdownHighlighter.Token], to storage: NSTextStorage, images: (String) -> NSImage? = { _ in nil },
               diagrams: (String) -> NSImage? = { _ in nil }, math: (String, Bool) -> MathPicture? = { _, _ in nil },
               revealed: NSRange = NSRange(location: 0, length: 0), textWidth: CGFloat = .greatestFiniteMagnitude) -> Resolved {
        let text = storage.string as NSString
        // The rendered look everywhere but the revealed lines, which keep the source look and get
        // the source presentation's coloring.
        for range in Self.complement(of: revealed, in: NSRange(location: 0, length: text.length)) where range.length > 0 {
            storage.addAttributes(style.renderedAttributes, range: range)
        }
        if revealed.length > 0 {
            for span in MarkdownHighlighter.spans(from: tokens) where NSLocationInRange(span.range.location, revealed) && NSMaxRange(span.range) <= text.length {
                storage.addAttributes(style.attributes(for: span.kind), range: span.range)
            }
        }
        let callouts = MarkdownHighlighter.calloutBlocks(in: tokens, text: text)
        for token in tokens where !NSLocationInRange(token.range.location, revealed) {
            let paragraph = text.paragraphRange(for: token.range)
            switch token.kind {
            case .heading(let level):
                let font = headingFont(level: level)
                let spaced = mutableParagraphStyle(at: paragraph.location, in: storage)
                spaced.lineHeightMultiple = style.lineHeightMultiple(for: font, lineHeight: PageTypography.headingLineHeight)
                var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: spaced]
                if level <= 2 {
                    // The page draws a divider under h1 and h2, with a little padding above it.
                    spaced.paragraphSpacing = (font.pointSize * 0.3).rounded()
                    attributes[.blockDecoration] = "heading"
                }
                storage.addAttributes(attributes, range: paragraph)
                storage.addAttributes([.font: font, .foregroundColor: level == 6 ? style.muted : style.foreground], range: token.range)
            case .strong:
                addTrait(.boldFontMask, to: storage, in: token.range)
            case .emphasis:
                addTrait(.italicFontMask, to: storage, in: token.range)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: token.range)
            case .inlineCode:
                // Mono at 85% of the surrounding text, in the text's color, like the page's `code`.
                // The tint stays off the backticks: a hidden marker at a paragraph start is laid out at
                // the end of the previous line, and a background there would fill that line to its edge.
                storage.addAttribute(.font, value: style.codeFont(within: font(at: token.range.location, in: storage)), range: token.range)
                let open = token.markers.first?.length ?? 0
                let close = token.markers.last?.length ?? 0
                let content = NSRange(location: token.range.location + open, length: max(0, token.range.length - open - close))
                storage.addAttribute(.backgroundColor, value: codeBackground, range: content)
            case .link(let destination), .autolink(let destination):
                storage.addAttributes([.foregroundColor: style.accent, .link: destination], range: token.range)
            case .image:
                storage.addAttribute(.foregroundColor, value: style.accent, range: token.range)
            case .listItem(let bullet, let box):
                // The item hangs by the width of its visible prefix (indentation, bullet or number,
                // and a task box's room); the box's brackets are hidden and its middle character is
                // kerned out to the box's width.
                var hanging = Self.width(of: visiblePrefix(of: token, bullet: bullet, box: box, from: paragraph.location, in: text), in: style.body)
                if let box {
                    let checked = text.character(at: box.location + 1) != 0x20
                    storage.addAttribute(.taskBox, value: checked ? "checked" : "unchecked", range: box)
                    let middle = NSRange(location: box.location + 1, length: 1)
                    let kern = max(0, Self.taskBoxWidth - Self.width(of: text.substring(with: middle), in: style.body))
                    storage.addAttribute(.kern, value: kern, range: middle)
                    hanging += kern
                }
                let hangingStyle = mutableParagraphStyle(at: paragraph.location, in: storage)
                hangingStyle.headIndent = hanging
                storage.addAttribute(.paragraphStyle, value: hangingStyle, range: paragraph)
            case .quote(let depth):
                let indented = mutableParagraphStyle(at: paragraph.location, in: storage)
                indented.firstLineHeadIndent = Self.quoteIndent * CGFloat(depth)
                indented.headIndent = indented.firstLineHeadIndent
                let stack = Self.decorationStack(at: token.range.location, depth: depth, in: callouts)
                if stack.contains(where: { $0.hasPrefix("callout:") }) {
                    // Inside a callout the text keeps its color, like the page's callout content.
                    storage.addAttributes([.paragraphStyle: indented, .blockDecoration: stack.joined(separator: "|")], range: paragraph)
                } else {
                    storage.addAttributes([.paragraphStyle: indented, .blockDecoration: "quote:\(depth)", .foregroundColor: style.muted], range: paragraph)
                }
            case .callout(let type, let depth, let defaultTitle):
                // The title hangs by the icon's room; the icon itself is drawn at the content's indent.
                let indented = mutableParagraphStyle(at: paragraph.location, in: storage)
                indented.firstLineHeadIndent = Self.quoteIndent * CGFloat(depth) + Self.calloutIconSize * style.scale + Self.calloutIconGap
                indented.headIndent = indented.firstLineHeadIndent
                indented.paragraphSpacingBefore = Self.calloutPadding
                let titleStart = token.markers.last.map { NSMaxRange($0) } ?? token.range.location
                let title = NSRange(location: titleStart, length: max(0, NSMaxRange(token.range) - titleStart))
                let hasTitle = !text.substring(with: title).trimmingCharacters(in: .whitespaces).isEmpty
                let stack = Self.decorationStack(at: token.range.location, depth: depth, in: callouts)
                storage.addAttributes([.paragraphStyle: indented, .blockDecoration: stack.joined(separator: "|"),
                                       .calloutTitle: CalloutTitle(type: type, depth: depth, defaultTitle: hasTitle ? nil : defaultTitle)], range: paragraph)
                storage.addAttributes([.font: style.calloutTitleFont, .foregroundColor: style.calloutColor(for: Callouts.role(for: type))], range: title)
            case .rule, .headingUnderline, .tableDelimiter:
                storage.addAttributes([.blockDecoration: "rule", .foregroundColor: style.muted], range: paragraph)
            case .footnoteReference:
                let label = NSRange(location: token.range.location + 2, length: token.range.length - 3)
                var attributes = style.scriptAttributes(within: font(at: label.location, in: storage))
                attributes[.foregroundColor] = style.accent
                storage.addAttributes(attributes, range: label)
            case .footnoteDefinition, .linkDefinition:
                storage.addAttribute(.foregroundColor, value: style.muted, range: token.range)
            case .html(let element, let attributes):
                apply(html: element, attributes: attributes, token: token, paragraph: paragraph, to: storage)
            case .escape:
                break
            case .tableRow(_, let isHeader, let pipes):
                for pipe in pipes {
                    storage.addAttribute(.foregroundColor, value: style.muted, range: NSRange(location: pipe, length: 1))
                }
                if isHeader {
                    addTrait(.boldFontMask, to: storage, in: token.range)
                }
            case .fence, .code, .mathFence:
                let codeFont = style.codeFont(within: style.body)
                let inset = mutableParagraphStyle(at: paragraph.location, in: storage)
                inset.lineHeightMultiple = style.lineHeightMultiple(for: codeFont, lineHeight: PageTypography.codeLineHeight)
                inset.firstLineHeadIndent = Self.codeIndent
                inset.headIndent = Self.codeIndent
                storage.addAttributes([.paragraphStyle: inset, .blockDecoration: "code", .font: codeFont], range: paragraph)
                storage.addAttribute(.foregroundColor, value: token.kind == .code ? style.foreground : style.muted, range: token.range)
            case .math(let display):
                let codeFont = style.codeFont(within: display && token.markers.isEmpty ? style.body : font(at: token.range.location, in: storage))
                if display, token.markers.isEmpty {
                    let inset = mutableParagraphStyle(at: paragraph.location, in: storage)
                    inset.lineHeightMultiple = style.lineHeightMultiple(for: codeFont, lineHeight: PageTypography.codeLineHeight)
                    inset.firstLineHeadIndent = Self.codeIndent
                    inset.headIndent = Self.codeIndent
                    storage.addAttributes([.paragraphStyle: inset, .blockDecoration: "code"], range: paragraph)
                }
                storage.addAttributes([.font: codeFont, .foregroundColor: style.code], range: token.range)
            case .frontMatter:
                storage.addAttributes([.font: style.codeFont(within: style.body), .foregroundColor: style.muted], range: token.range)
            }
            for marker in token.markers {
                storage.addAttribute(.foregroundColor, value: style.muted, range: marker)
            }
        }
        for block in callouts where !Self.touches(revealed, block.range) {
            // Room under the block's last line, inside the box.
            let last = text.paragraphRange(for: NSRange(location: NSMaxRange(block.range), length: 0))
            let spaced = mutableParagraphStyle(at: last.location, in: storage)
            spaced.paragraphSpacing = max(spaced.paragraphSpacing, Self.calloutPadding)
            storage.addAttribute(.paragraphStyle, value: spaced, range: last)
        }
        alignTables(tokens, in: storage, revealed: revealed)
        let blocks = Self.fencedBlocks(in: tokens, text: text)
        return Resolved(images: reserveImages(tokens, in: storage, images: images, revealed: revealed, textWidth: textWidth),
                        diagrams: reserveDiagrams(blocks, in: storage, diagrams: diagrams, revealed: revealed, textWidth: textWidth),
                        math: reserveMath(tokens, blocks: blocks, in: storage, math: math, revealed: revealed, textWidth: textWidth),
                        pictureBlocks: blocks.filter { $0.isDiagram || $0.isMath }.map(\.range))
    }

    /// One entry per quote level of a line at `location`: `callout:<type>` where a callout block of
    /// that depth holds the line, `quote` otherwise.
    static func decorationStack(at location: Int, depth: Int, in callouts: [MarkdownHighlighter.CalloutBlock]) -> [String] {
        (1...max(depth, 1)).map { level in
            callouts.first { $0.depth == level && NSLocationInRange(location, $0.range) }.map { "callout:\($0.type)" } ?? "quote"
        }
    }

    /// The parts of `whole` outside `range`: where the rendered look goes.
    static func complement(of range: NSRange, in whole: NSRange) -> [NSRange] {
        let clamped = NSIntersectionRange(range, whole)
        guard clamped.length > 0 else { return [whole] }
        return [NSRange(location: whole.location, length: clamped.location - whole.location),
                NSRange(location: NSMaxRange(clamped), length: NSMaxRange(whole) - NSMaxRange(clamped))]
    }

    /// Whether the revealed range reaches into `range`; an empty one (nothing revealed) never does.
    private static func touches(_ revealed: NSRange, _ range: NSRange) -> Bool {
        revealed.length > 0 && (NSIntersectionRange(range, revealed).length > 0 || NSLocationInRange(revealed.location, range))
    }

    private func font(at index: Int, in storage: NSTextStorage) -> NSFont {
        guard index < storage.length else { return style.body }
        return storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont ?? style.body
    }

    /// A copy of the paragraph style in force at `index` (the rendered base, or what an earlier token set).
    private func mutableParagraphStyle(at index: Int, in storage: NSTextStorage) -> NSMutableParagraphStyle {
        guard index < storage.length,
              let existing = storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle,
              let copy = existing.mutableCopy() as? NSMutableParagraphStyle else {
            return style.paragraphStyle(for: style.body, lineHeight: style.typography.lineHeight)
        }
        return copy
    }

    /// A list item's prefix as it shows: from the line start through the marker and its spacing,
    /// without a task box's brackets, the bullet as the bullet glyph it is drawn with.
    private func visiblePrefix(of token: MarkdownHighlighter.Token, bullet: Int?, box: NSRange?, from lineStart: Int, in text: NSString) -> String {
        var prefix = ""
        for index in lineStart..<NSMaxRange(token.range) {
            if let box, index == box.location || index == NSMaxRange(box) - 1 { continue }
            if index == bullet {
                prefix.append("•")
            } else {
                prefix.append(Character(UnicodeScalar(text.character(at: index)) ?? " "))
            }
        }
        return prefix
    }

    /// What HTML can look like in a text view: the common inline tags map to font traits, colors
    /// and offsets on the element's content, `align` and `<center>` set the paragraph's alignment,
    /// a lone `<hr>` becomes a rule. The tags themselves are markers.
    private func apply(html element: String?, attributes: [String: String], token: MarkdownHighlighter.Token, paragraph: NSRange, to storage: NSTextStorage) {
        guard let element else { return }
        let text = storage.string as NSString
        let alignments: [String: NSTextAlignment] = ["left": .left, "center": .center, "right": .right]
        if let alignment = attributes["align"].flatMap({ alignments[$0.lowercased()] }) {
            setAlignment(alignment, of: paragraph, in: storage)
        } else if element == "center" {
            setAlignment(.center, of: paragraph, in: storage)
        }
        if element == "hr", text.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines) == text.substring(with: token.range) {
            storage.addAttributes([.blockDecoration: "rule"], range: paragraph)
        }
        guard token.markers.count == 2 else { return }
        let content = NSRange(location: NSMaxRange(token.markers[0]), length: token.markers[1].location - NSMaxRange(token.markers[0]))
        guard content.length > 0 else { return }
        switch element {
        case "b", "strong":
            addTrait(.boldFontMask, to: storage, in: content)
        case "i", "em", "cite", "dfn", "var":
            addTrait(.italicFontMask, to: storage, in: content)
        case "u", "ins":
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: content)
        case "s", "del", "strike":
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
        case "code", "kbd", "samp", "tt":
            storage.addAttributes([.font: style.codeFont(within: font(at: content.location, in: storage)), .backgroundColor: codeBackground], range: content)
        case "mark":
            storage.addAttribute(.backgroundColor, value: style.accent.withAlphaComponent(0.25), range: content)
        case "sup":
            storage.addAttributes(style.scriptAttributes(within: font(at: content.location, in: storage)), range: content)
        case "sub":
            storage.addAttributes(style.scriptAttributes(within: font(at: content.location, in: storage), lowered: true), range: content)
        case "a":
            storage.addAttribute(.foregroundColor, value: style.accent, range: content)
            if let destination = attributes["href"], !destination.isEmpty {
                storage.addAttribute(.link, value: destination, range: content)
            }
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(element.dropFirst()) ?? 6
            storage.addAttributes([.font: headingFont(level: level), .foregroundColor: level == 6 ? style.muted : style.foreground], range: content)
        default:
            break
        }
    }

    private func setAlignment(_ alignment: NSTextAlignment, of paragraph: NSRange, in storage: NSTextStorage) {
        let aligned = mutableParagraphStyle(at: paragraph.location, in: storage)
        aligned.alignment = alignment
        storage.addAttribute(.paragraphStyle, value: aligned, range: paragraph)
    }

    /// Pads every cell of a rendered row to its column's width with kerning, in points: after the
    /// cell's last visible character for left alignment, after its leading space for right, split
    /// for center. Column widths come from every row's rendered width, revealed rows included, so
    /// the caret entering a row moves nothing else.
    private func alignTables(_ tokens: [MarkdownHighlighter.Token], in storage: NSTextStorage, revealed: NSRange) {
        let markers = MarkerIndex(tokens: tokens)
        let text = storage.string as NSString
        for table in Self.tables(in: tokens) {
            let widths = table.map { row in row.cells.map { renderedWidth(of: $0, header: row.isHeader, in: row.range, tokens: tokens, markers: markers, text: text) } }
            let columns = widths.map(\.count).max() ?? 0
            let columnWidths = (0..<columns).map { column in widths.compactMap { $0.indices.contains(column) ? $0[column] : nil }.max() ?? 0 }
            for (row, rowWidths) in zip(table, widths) where !NSLocationInRange(row.range.location, revealed) {
                for (cell, width) in zip(row.cells, rowWidths) {
                    guard let index = row.cells.firstIndex(where: { $0.range == cell.range }) else { continue }
                    let padding = columnWidths[index] - width
                    guard padding > 0.5 else { continue }
                    let before: CGFloat
                    switch cell.alignment {
                    case .left: before = 0
                    case .right: before = padding
                    case .center: before = (padding / 2).rounded()
                    }
                    let after = padding - before
                    if after > 0, let last = lastVisibleCharacter(in: cell.range, markers: markers) {
                        storage.addAttribute(.kern, value: after, range: NSRange(location: last, length: 1))
                    }
                    if before > 0, cell.range.length > 0, text.character(at: cell.range.location) == 0x20, !markers.isHidden(cell.range.location) {
                        storage.addAttribute(.kern, value: before, range: NSRange(location: cell.range.location, length: 1))
                    }
                }
            }
        }
    }

    private struct TableRow {
        let range: NSRange
        let cells: [MarkdownHighlighter.TableCell]
        let isHeader: Bool
    }

    /// Rows on consecutive lines (with the delimiter between them) form one table.
    private static func tables(in tokens: [MarkdownHighlighter.Token]) -> [[TableRow]] {
        var tables: [[TableRow]] = []
        var current: [TableRow] = []
        var lastEnd = Int.min
        for token in tokens {
            switch token.kind {
            case .tableRow(let cells, let isHeader, _):
                if token.range.location != lastEnd + 1, !current.isEmpty {
                    tables.append(current)
                    current = []
                }
                current.append(TableRow(range: token.range, cells: cells, isHeader: isHeader))
                lastEnd = NSMaxRange(token.range)
            case .tableDelimiter:
                lastEnd = NSMaxRange(token.range)
            default:
                continue
            }
        }
        if !current.isEmpty { tables.append(current) }
        return tables
    }

    /// The width a cell takes once rendered: its visible characters in the body font, bold in the
    /// header row or inside `**…**`, the mono code font inside backticks.
    private func renderedWidth(of cell: MarkdownHighlighter.TableCell, header: Bool, in row: NSRange, tokens: [MarkdownHighlighter.Token], markers: MarkerIndex, text: NSString) -> CGFloat {
        let bold = NSFontManager.shared.convert(style.body, toHaveTrait: .boldFontMask)
        let code = style.codeFont(within: style.body)
        var codeRanges: [NSRange] = []
        var boldRanges: [NSRange] = []
        for token in tokens where NSIntersectionRange(token.range, row).length > 0 {
            switch token.kind {
            case .inlineCode: codeRanges.append(token.range)
            case .strong: boldRanges.append(token.range)
            default: break
            }
        }
        func font(at index: Int) -> NSFont {
            if codeRanges.contains(where: { NSLocationInRange(index, $0) }) { return code }
            if header || boldRanges.contains(where: { NSLocationInRange(index, $0) }) { return bold }
            return style.body
        }
        var width: CGFloat = 0
        var index = cell.range.location
        let end = NSMaxRange(cell.range)
        while index < end {
            guard !markers.isHidden(index) else {
                index += 1
                continue
            }
            let runFont = font(at: index)
            var runEnd = index + 1
            while runEnd < end, !markers.isHidden(runEnd), font(at: runEnd) == runFont { runEnd += 1 }
            width += Self.width(of: text.substring(with: NSRange(location: index, length: runEnd - index)), in: runFont)
            index = runEnd
        }
        return width
    }

    /// The last character of the cell that is not a hidden marker; for an empty cell, the pipe before it.
    private func lastVisibleCharacter(in range: NSRange, markers: MarkerIndex) -> Int? {
        var index = NSMaxRange(range) - 1
        while index >= range.location {
            if !markers.isHidden(index) { return index }
            index -= 1
        }
        return range.location > 0 && !markers.isHidden(range.location - 1) ? range.location - 1 : nil
    }

    /// The first image of a rendered paragraph that loads gets drawn under it: the paragraph's
    /// spacing grows by the fitted height plus a gap, and the picture rides along as an attribute.
    private func reserveImages(_ tokens: [MarkdownHighlighter.Token], in storage: NSTextStorage, images: (String) -> NSImage?, revealed: NSRange, textWidth: CGFloat) -> Set<Int> {
        let text = storage.string as NSString
        var resolved: Set<Int> = []
        var decorated: Set<Int> = []
        for token in tokens {
            guard case .image(let destination) = token.kind else { continue }
            let paragraph = text.paragraphRange(for: token.range)
            guard !decorated.contains(paragraph.location), !Self.touches(revealed, paragraph), let image = images(destination),
                  image.size.width > 0, image.size.height > 0 else { continue }
            let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            let available = max(40, textWidth - (existing?.headIndent ?? 0))
            let scale = min(1, available / image.size.width, Self.maximumImageHeight / image.size.height)
            let size = NSSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
            let spaced = mutableParagraphStyle(at: paragraph.location, in: storage)
            spaced.paragraphSpacing = size.height + Self.imageGap
            storage.addAttributes([.paragraphStyle: spaced, .inlineImage: InlineImage(image: image, size: size)], range: paragraph)
            decorated.insert(paragraph.location)
            resolved.insert(token.range.location)
        }
        return resolved
    }

    /// A mermaid fence outside `revealed` whose picture is ready collapses to one blank line with the
    /// picture under it: `MarkerIndex` hides the block's glyphs but for the last newline, the code
    /// decoration goes, and the closing line's paragraph reserves the picture's height like an image's.
    private func reserveDiagrams(_ blocks: [FencedBlock], in storage: NSTextStorage, diagrams: (String) -> NSImage?, revealed: NSRange, textWidth: CGFloat) -> Set<Int> {
        let text = storage.string as NSString
        var resolved: Set<Int> = []
        for block in blocks where block.isDiagram {
            guard block.range.length > 0, !Self.touches(revealed, block.range),
                  let image = diagrams(MermaidRenderer.key(for: block.lines.joined(separator: "\n"))), image.size.width > 0, image.size.height > 0 else { continue }
            let available = max(40, textWidth)
            let scale = min(1, available / image.size.width, Self.maximumDiagramHeight / image.size.height)
            let size = NSSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
            storage.removeAttribute(.blockDecoration, range: text.paragraphRange(for: block.range))
            let last = text.paragraphRange(for: NSRange(location: NSMaxRange(block.range) - 1, length: 0))
            let spaced = mutableParagraphStyle(at: last.location, in: storage)
            spaced.paragraphSpacing = size.height + Self.imageGap
            storage.addAttributes([.paragraphStyle: spaced, .inlineImage: InlineImage(image: image, size: size)], range: last)
            resolved.insert(block.range.location)
        }
        return resolved
    }

    /// A formula outside `revealed` whose picture is ready is drawn in place of its TeX. The picture
    /// rides on one character, the anchor: the opening dollar, or for a `$$` or ```math block the
    /// closing fence's first character, so that the block's other lines (hidden, they attach to the
    /// previous line) collapse and the anchor's paragraph keeps its newline. `MarkerIndex` hides the
    /// rest and `ThemedTextView` lays the anchor out as a box of the picture's size. A display formula
    /// alone on its line is centered; a block also loses its code look.
    private func reserveMath(_ tokens: [MarkdownHighlighter.Token], blocks: [FencedBlock], in storage: NSTextStorage, math: (String, Bool) -> MathPicture?, revealed: NSRange, textWidth: CGFloat) -> [Int: Int] {
        let text = storage.string as NSString
        var resolved: [Int: Int] = [:]
        for token in tokens {
            guard case .math(let display) = token.kind, token.markers.count == 2, !Self.touches(revealed, token.range) else { continue }
            let open = NSMaxRange(token.markers[0])
            let tex = text.substring(with: NSRange(location: open, length: max(0, token.markers[1].location - open))).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tex.isEmpty, let picture = math(tex, display) else { continue }
            let paragraph = text.paragraphRange(for: token.range)
            let indent = (storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
            let anchor = token.range.location
            storage.addAttribute(.mathPicture, value: picture.fitted(to: max(40, textWidth - indent)), range: NSRange(location: anchor, length: 1))
            if display, text.substring(with: paragraph).trimmingCharacters(in: .whitespacesAndNewlines) == text.substring(with: token.range) {
                setAlignment(.center, of: paragraph, in: storage)
            }
            resolved[anchor] = anchor
        }
        for block in blocks where block.isMath {
            let tex = block.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let closing = block.closing, !tex.isEmpty, !Self.touches(revealed, block.range), let picture = math(tex, true) else { continue }
            let paragraphs = text.paragraphRange(for: block.range)
            storage.removeAttribute(.blockDecoration, range: paragraphs)
            let centered = mutableParagraphStyle(at: paragraphs.location, in: storage)
            centered.alignment = .center
            storage.addAttribute(.paragraphStyle, value: centered, range: paragraphs)
            storage.addAttribute(.mathPicture, value: picture.fitted(to: max(40, textWidth)), range: NSRange(location: closing, length: 1))
            resolved[block.range.location] = closing
        }
        return resolved
    }

    /// Every fenced block in order: ``` and ~~~ fences with their info string, `$$` blocks as `math`.
    static func fencedBlocks(in tokens: [MarkdownHighlighter.Token], text: NSString) -> [FencedBlock] {
        var blocks: [FencedBlock] = []
        var open: (start: Int, info: String)?
        var end = 0
        var lines: [String] = []
        for token in tokens {
            switch token.kind {
            case .fence, .mathFence:
                if let current = open {
                    blocks.append(FencedBlock(range: NSRange(location: current.start, length: NSMaxRange(token.range) - current.start), info: current.info, lines: lines, closing: token.range.location))
                    open = nil
                } else {
                    let info: String
                    if token.kind == .mathFence {
                        info = "math"
                    } else {
                        let markerEnd = token.markers.first.map { NSMaxRange($0) } ?? token.range.location
                        info = text.substring(with: NSRange(location: markerEnd, length: max(0, NSMaxRange(token.range) - markerEnd)))
                    }
                    open = (token.range.location, info)
                    end = NSMaxRange(token.range)
                    lines = []
                }
            case .code, .math:
                guard open != nil else { continue }
                lines.append(text.substring(with: token.range))
                end = NSMaxRange(token.range)
            default:
                break
            }
        }
        if let current = open {
            blocks.append(FencedBlock(range: NSRange(location: current.start, length: max(end, current.start) - current.start), info: current.info, lines: lines, closing: nil))
        }
        return blocks
    }

    /// The fenced blocks whose info string starts with `mermaid`.
    static func diagramBlocks(in tokens: [MarkdownHighlighter.Token], text: NSString) -> [DiagramBlock] {
        fencedBlocks(in: tokens, text: text).filter(\.isDiagram)
            .map { DiagramBlock(range: $0.range, source: MermaidRenderer.key(for: $0.lines.joined(separator: "\n"))) }
    }

    private func addTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? style.regular
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }
}
