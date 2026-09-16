import AppKit
import UncialCore

extension NSAttributedString.Key {
    /// Paragraph decoration drawn by `InlineLayoutManager`: "code", "quote:N" or "rule".
    static let blockDecoration = NSAttributedString.Key("uncialBlockDecoration")
    /// A task box `[ ]`/`[x]` drawn by `InlineLayoutManager`: "unchecked" or "checked".
    static let taskBox = NSAttributedString.Key("uncialTaskBox")
    /// An `InlineImage` drawn by `InlineLayoutManager` in the paragraph's reserved spacing.
    static let inlineImage = NSAttributedString.Key("uncialInlineImage")
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

/// Attributes for the inline presentation: headings sized, markers muted, code on a background,
/// list items hanging, quotes indented behind a border, links in the accent color. Attribute-only,
/// so undo never sees it; the fonts stay SF Mono.
struct InlineStyle {
    static let headingSizes: [CGFloat] = [22, 19, 16, 14, 13, 13]
    static let quoteIndent: CGFloat = 16
    static let codeIndent: CGFloat = 12
    static let maximumImageHeight: CGFloat = 480
    static let maximumDiagramHeight: CGFloat = 800
    static let imageGap: CGFloat = 8

    /// What `apply` drew as pictures: the image tokens' locations and the opening fences of diagrams.
    struct Resolved: Equatable {
        var images: Set<Int> = []
        var diagrams: Set<Int> = []
    }

    /// A mermaid fence: `range` spans both fence lines (an unclosed one ends at its last code
    /// line), `source` is the diagram text as `MermaidRenderer.key(for:)` normalizes it.
    struct DiagramBlock: Equatable {
        let range: NSRange
        let source: String
    }

    let style: EditorStyle
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

    func headingFont(level: Int) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: Self.headingSizes[max(1, min(level, 6)) - 1] * style.scale, weight: .bold)
    }

    /// `storage` must already carry the base attributes for its whole text. `images` loads an
    /// image token's destination and `diagrams` a mermaid fence's picture (nil keeps either as
    /// source; a fence inside `revealed` is never asked for); `textWidth` is the room for text, which
    /// bounds the drawn sizes. Returns what got a picture.
    @discardableResult
    func apply(_ tokens: [MarkdownHighlighter.Token], to storage: NSTextStorage, images: (String) -> NSImage? = { _ in nil },
               diagrams: (String) -> NSImage? = { _ in nil }, revealed: NSRange = NSRange(location: 0, length: 0),
               textWidth: CGFloat = .greatestFiniteMagnitude) -> Resolved {
        let text = storage.string as NSString
        for token in tokens {
            let paragraph = text.paragraphRange(for: token.range)
            switch token.kind {
            case .heading(let level):
                storage.addAttributes([.font: headingFont(level: level), .foregroundColor: level == 6 ? style.muted : style.foreground], range: token.range)
            case .strong:
                addTrait(.boldFontMask, to: storage, in: token.range)
            case .emphasis:
                addTrait(.italicFontMask, to: storage, in: token.range)
            case .strikethrough:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: token.range)
            case .inlineCode:
                // The tint stays off the backticks: a hidden marker at a paragraph start is laid out at
                // the end of the previous line, and a background there would fill that line to its edge.
                storage.addAttribute(.foregroundColor, value: style.code, range: token.range)
                let open = token.markers.first?.length ?? 0
                let close = token.markers.last?.length ?? 0
                let content = NSRange(location: token.range.location + open, length: max(0, token.range.length - open - close))
                storage.addAttribute(.backgroundColor, value: codeBackground, range: content)
            case .link(let destination), .autolink(let destination):
                storage.addAttributes([.foregroundColor: style.accent, .link: destination], range: token.range)
            case .image:
                storage.addAttribute(.foregroundColor, value: style.accent, range: token.range)
            case .listItem(_, let box):
                storage.addAttribute(.foregroundColor, value: style.accent, range: token.range)
                if let box {
                    let checked = text.character(at: box.location + 1) != 0x20
                    storage.addAttribute(.taskBox, value: checked ? "checked" : "unchecked", range: box)
                }
                // The box's brackets are hidden, so the visible prefix is two characters shorter.
                let hanging = NSMutableParagraphStyle()
                hanging.headIndent = characterWidth * CGFloat(token.range.length - (box == nil ? 0 : 2))
                storage.addAttribute(.paragraphStyle, value: hanging, range: paragraph)
            case .quote(let depth):
                let indented = NSMutableParagraphStyle()
                indented.firstLineHeadIndent = Self.quoteIndent * CGFloat(depth)
                indented.headIndent = indented.firstLineHeadIndent
                storage.addAttributes([.paragraphStyle: indented, .blockDecoration: "quote:\(depth)", .foregroundColor: style.muted], range: paragraph)
            case .rule, .headingUnderline, .tableDelimiter:
                storage.addAttributes([.blockDecoration: "rule", .foregroundColor: style.muted], range: paragraph)
            case .footnoteReference:
                let label = NSRange(location: token.range.location + 2, length: token.range.length - 3)
                storage.addAttributes([.font: superscriptFont, .baselineOffset: CGFloat(4), .foregroundColor: style.accent], range: label)
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
                let inset = NSMutableParagraphStyle()
                inset.firstLineHeadIndent = Self.codeIndent
                inset.headIndent = Self.codeIndent
                storage.addAttributes([.paragraphStyle: inset, .blockDecoration: "code"], range: paragraph)
                storage.addAttribute(.foregroundColor, value: token.kind == .code ? style.code : style.muted, range: token.range)
            case .math(let display):
                if display, token.markers.isEmpty {
                    let inset = NSMutableParagraphStyle()
                    inset.firstLineHeadIndent = Self.codeIndent
                    inset.headIndent = Self.codeIndent
                    storage.addAttributes([.paragraphStyle: inset, .blockDecoration: "code"], range: paragraph)
                }
                storage.addAttribute(.foregroundColor, value: style.code, range: token.range)
            case .frontMatter:
                storage.addAttribute(.foregroundColor, value: style.muted, range: token.range)
            }
            for marker in token.markers {
                storage.addAttribute(.foregroundColor, value: style.muted, range: marker)
            }
        }
        alignTables(tokens, in: storage)
        return Resolved(images: reserveImages(tokens, in: storage, images: images, textWidth: textWidth),
                        diagrams: reserveDiagrams(tokens, in: storage, diagrams: diagrams, revealed: revealed, textWidth: textWidth))
    }

    var superscriptFont: NSFont { NSFont.monospacedSystemFont(ofSize: 10 * style.scale, weight: .bold) }

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
            storage.addAttributes([.foregroundColor: style.code, .backgroundColor: codeBackground], range: content)
        case "mark":
            storage.addAttribute(.backgroundColor, value: style.accent.withAlphaComponent(0.25), range: content)
        case "sup":
            storage.addAttributes([.font: superscriptFont, .baselineOffset: CGFloat(4)], range: content)
        case "sub":
            storage.addAttributes([.font: superscriptFont, .baselineOffset: CGFloat(-3)], range: content)
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
        let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
        let aligned = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        aligned.alignment = alignment
        storage.addAttribute(.paragraphStyle, value: aligned, range: paragraph)
    }

    /// Pads every cell to its column's width with kerning: after the cell's last visible character
    /// for left alignment, after its leading space for right, split for center. SF Mono makes the
    /// padding an exact number of character cells.
    private func alignTables(_ tokens: [MarkdownHighlighter.Token], in storage: NSTextStorage) {
        let markers = MarkerIndex(tokens: tokens)
        let text = storage.string as NSString
        for token in tokens {
            guard case .tableRow(let cells, _, _) = token.kind else { continue }
            for cell in cells {
                let padding = cell.columnWidth - cell.visibleWidth
                guard padding > 0 else { continue }
                let before: Int
                switch cell.alignment {
                case .left: before = 0
                case .right: before = padding
                case .center: before = padding / 2
                }
                let after = padding - before
                if after > 0, let last = lastVisibleCharacter(in: cell.range, markers: markers) {
                    storage.addAttribute(.kern, value: characterWidth * CGFloat(after), range: NSRange(location: last, length: 1))
                }
                if before > 0, cell.range.length > 0, text.character(at: cell.range.location) == 0x20, !markers.isHidden(cell.range.location) {
                    storage.addAttribute(.kern, value: characterWidth * CGFloat(before), range: NSRange(location: cell.range.location, length: 1))
                }
            }
        }
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

    /// The first image of a paragraph that loads gets drawn under it: the paragraph's spacing
    /// grows by the fitted height plus a gap, and the picture rides along as an attribute.
    private func reserveImages(_ tokens: [MarkdownHighlighter.Token], in storage: NSTextStorage, images: (String) -> NSImage?, textWidth: CGFloat) -> Set<Int> {
        let text = storage.string as NSString
        var resolved: Set<Int> = []
        var decorated: Set<Int> = []
        for token in tokens {
            guard case .image(let destination) = token.kind else { continue }
            let paragraph = text.paragraphRange(for: token.range)
            guard !decorated.contains(paragraph.location), let image = images(destination),
                  image.size.width > 0, image.size.height > 0 else { continue }
            let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            let available = max(40, textWidth - (existing?.headIndent ?? 0))
            let scale = min(1, available / image.size.width, Self.maximumImageHeight / image.size.height)
            let size = NSSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
            let spaced = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
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
    private func reserveDiagrams(_ tokens: [MarkdownHighlighter.Token], in storage: NSTextStorage, diagrams: (String) -> NSImage?, revealed: NSRange, textWidth: CGFloat) -> Set<Int> {
        let text = storage.string as NSString
        var resolved: Set<Int> = []
        for block in Self.diagramBlocks(in: tokens, text: text) {
            guard block.range.length > 0, NSIntersectionRange(block.range, revealed).length == 0, !NSLocationInRange(revealed.location, block.range),
                  let image = diagrams(block.source), image.size.width > 0, image.size.height > 0 else { continue }
            let available = max(40, textWidth)
            let scale = min(1, available / image.size.width, Self.maximumDiagramHeight / image.size.height)
            let size = NSSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
            storage.removeAttribute(.blockDecoration, range: text.paragraphRange(for: block.range))
            let last = text.paragraphRange(for: NSRange(location: NSMaxRange(block.range) - 1, length: 0))
            let spaced = NSMutableParagraphStyle()
            spaced.paragraphSpacing = size.height + Self.imageGap
            storage.addAttributes([.paragraphStyle: spaced, .inlineImage: InlineImage(image: image, size: size)], range: last)
            resolved.insert(block.range.location)
        }
        return resolved
    }

    /// The fenced blocks whose info string starts with `mermaid`.
    static func diagramBlocks(in tokens: [MarkdownHighlighter.Token], text: NSString) -> [DiagramBlock] {
        var blocks: [DiagramBlock] = []
        var start: Int?
        var end = 0
        var lines: [String] = []
        var isDiagram = false
        func close(_ open: Int, at end: Int) {
            guard isDiagram, !lines.isEmpty else { return }
            blocks.append(DiagramBlock(range: NSRange(location: open, length: end - open), source: MermaidRenderer.key(for: lines.joined(separator: "\n"))))
        }
        for token in tokens {
            switch token.kind {
            case .fence:
                if let open = start {
                    close(open, at: NSMaxRange(token.range))
                    start = nil
                } else {
                    start = token.range.location
                    end = NSMaxRange(token.range)
                    lines = []
                    let markerEnd = token.markers.first.map { NSMaxRange($0) } ?? token.range.location
                    let info = text.substring(with: NSRange(location: markerEnd, length: max(0, NSMaxRange(token.range) - markerEnd)))
                    isDiagram = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first == "mermaid"
                }
            case .code:
                if start != nil {
                    lines.append(text.substring(with: token.range))
                    end = NSMaxRange(token.range)
                }
            default:
                break
            }
        }
        if let open = start {
            close(open, at: end)
        }
        return blocks
    }

    private func addTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? style.regular
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }
}
