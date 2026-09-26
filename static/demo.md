---
title: Uncial demo
tags: [demo, visual-test]
---

# Uncial demo

This document is the standard file for visual checks. Open it in every mode
(⌥⌘1 Read Only, ⌥⌘2 Live Preview, ⌥⌘3 Split View, ⌥⌘4 Raw Editor) and compare
each section with its *Expect* line. Keep the sections and their order stable
so that probes and screenshots stay comparable.

## Headings

### Level three
#### Level four
##### Level five
###### Level six is muted

Setext level one
================

Setext level two
----------------

*Expect:* Live Preview shows the headings like the rendered page: the system
font at the theme's sizes (26/22/17/15/13/13 for macOS, 2em down to .85em of
the body for GitHub and Solarized), level six muted, a divider under level one
and two, setext underlines drawn as rules, the `#` markers hidden. Only the
cursor's line shows its source, in SF Mono like the Raw Editor.

## Inline styles

Plain text with **bold**, *italic*, ***bold italic***, ~~strikethrough~~,
`inline code`, and a [link to the repository](https://github.com/vflame6/uncial).
An autolink: <https://example.com>. Escapes stay literal: \*not italic\*, 3 \* 4,
snake_case, ~5 min, and 2 * 3 * 4.

A footnote reference[^note] and inline <b>HTML</b> tags <!-- with a comment -->.

[^note]: Footnote definitions render on their own line.

*Expect:* markers hidden off the cursor line; the cursor's line is the raw
source, colored like the Raw Editor, on a tinted band with room above and below
(its line number on its baseline); body text in the theme's page font, the code
in the mono font on a tint; the link is in the accent color and ⌘-click opens it; the
footnote mark is a small raised "note"; escape backslashes and HTML tags hide
with the other markers, so the comment vanishes and HTML reads bold.

## Lists

- Bullet item
- Bullet with **bold**, `code` and a [link](https://example.com)
  - Nested bullet
    - Third level
- A long bullet that keeps going long enough to wrap onto a second visual line in the readable column so the hanging indent under the text can be checked.
1. First numbered item
2. Second numbered item
   1. Nested numbered item
   2. Another nested item
- [ ] Open task
- [x] Done task
- [ ] Task with *emphasis* and a [link](https://example.com)

*Expect:* bullets drawn as •, numbers in the text color like the page, wrapped
lines hanging under their text, task boxes drawn as squares that toggle on click
(undoable, an edit like typing).

## Quotes

> A quoted paragraph with **bold** text and `code`.
> A second line of the same quote.
>
> > A nested quote.

*Expect:* one bar per level in the muted color, `>` markers hidden, the text
muted.

## Callouts

> [!note] A titled note
> Body text with **bold** and `code`.

> [!tip]
> The title falls back to the type.

> [!warning]- Folded, closed by default
> Hidden until the title is clicked.

> [!example] Nested
> > [!todo] Inner callout
> > with a step
> > > a plain quote inside

*Expect:* one tinted box per callout with the type's icon and title in its color
(blue note, teal tip, orange warning, purple example), the body in the text color;
the folded warning shows a chevron and opens on click in the page; in Live Preview
the boxes are drawn in place and the whole callout shows its source while the
cursor is inside; the plain quote inside keeps its bar.

## Code

```swift
struct Demo {
    let answer = 42   // a comment
    func run() -> Int { answer * 2 }
}
```

```python
def greet(name: str) -> str:
    """Say hello,
    on two lines."""
    return f"Hello, {name}!"  # trailing
```

```json
{ "name": "uncial", "version": 1.0, "themes": ["macOS", "GitHub", "Solarized"] }
```

```diff
- let old = true
+ let new = false
```

~~~
A tilde fence without an info string.
~~~

    An indented code block (four spaces) stays as source in Live Preview.

*Expect:* fenced blocks on a rounded tint spanning every line, fence lines
hidden except the info string, keywords, strings, numbers and comments in the
theme's syntax colors (the same colors in the rendered page and in Quick Look;
the docstring stays one color across its two lines, the diff lines get a green
and a red tint), the tilde fence in the plain code color. Put the cursor inside
a block: the whole block shows its source like the Raw Editor, without the tint.

## Table

| Name   | Qty | Price | Note                        |
|:-------|----:|:-----:|-----------------------------|
| Apple  |   3 |  1.20 | **fresh**                   |
| Banana |  12 |  0.50 | with `code`                 |
| Cherry | 100 | 12.00 | [link](https://example.com) |

*Expect:* columns aligned (Qty right, Price centered), header bold, delimiter
row drawn as a rule, outer pipes hidden, inner pipes muted; the cursor's row
shows its raw pipes in SF Mono, unpadded, and the other rows keep their columns.

## Rules

Text above a rule.

---

* * *

*Expect:* two thin lines; the second one comes from spaced asterisks. The `---`
right under "Setext level two" above is a heading underline, not a rule.

## Images

![Uncial icon](icon.png)

A remote image: ![Rickrolling QR code](https://upload.wikimedia.org/wikipedia/commons/2/2f/Rickrolling_QR_code.png)

*Expect:* the local icon drawn under its line at 128 pt with the alt text above
it; the remote one appears the same way once it has loaded (Live Preview and the
rendered page both fetch it; Quick Look has no network and shows nothing).

## Links and anchors

Jump to [Headings](#headings) or [Table](#table). A reference-style link
[renders like an inline one][ref]; its definition line below stays muted.

[ref]: https://example.com

A link to a local Markdown file opens a new Uncial window: [this file](demo.md).

## HTML

<div align="center">This div is centered in Live Preview and in the rendered page.</div>

Inline tags: <b>bold</b>, <i>italic</i>, <u>underlined</u>, <kbd>⌘</kbd>, H<sub>2</sub>O,
x<sup>2</sup>, <mark>marked</mark>, <a href="https://example.com">a link</a>, and an image tag:

<img src="icon.png" alt="icon">

*Expect:* tags hidden off the cursor line, the div text centered, the inline tags styled like
their Markdown equivalents, the image drawn under its line at 128 pt. A multi-line block only
hides its tag lines; comments and `<br>` leave nothing behind.

## Math

Inline math $E = mc^2$ and $\frac{a}{b}$ sit in the text; prices like $5 and $10
are not math. Display math stands alone:

$$
\int_0^1 x^2 \, dx = \frac{1}{3}
$$

```math
\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}
```

*Expect:* the rendered page shows real formulas (KaTeX to MathML, no script); Live
Preview draws them too, inline on the baseline and display math centered on its own
line, and shows the TeX (dollars hidden, the `$$` block tinted like code) only on
the caret's line or block. Bad TeX shows in red with its source, in both.

## Diagrams

```mermaid
graph LR
  A[Open file] --> B{Changed on disk?}
  B -->|Yes| C[Re-render]
  B -->|No| D[Keep going]
```

```mermaid
sequenceDiagram
  Finder->>Uncial: Space
  Uncial-->>Finder: rendered preview
```

```mermaid
pie title Pets
  "Dogs" : 386
  "Cats" : 85
```

```mermaid
gantt
  title Release
  dateFormat YYYY-MM-DD
  section Build
  Tests :a1, 2026-09-01, 5d
  Ship  :after a1, 2d
```

```mermaid
mindmap
  root((Uncial))
    Reader
    Editor
      Live Preview
```

*Expect:* every diagram is a vector drawing in the theme's colors: in the rendered page, in Quick
Look, and in Live Preview, where a fence shows its source only while the caret is inside it.
Flowcharts, sequence, state, class and ER diagrams and XY charts come from beautiful-mermaid and
follow the theme live; everything else comes from mermaid.js in a hidden web view, drawn once
per appearance. No script runs in the page.

## Not rendered on purpose

Front matter and reference link definitions stay visible but muted.

## Find and status bar

The word needle appears three times in this paragraph: needle, and once more,
needle. Use ⌘F in every mode; the Read Only bar should report "3 found" when
searching for needle. 🔥 Emoji count as characters, not words; don't, well-known
and 3,857 are one word each.

## Editing checks (Live Preview or Raw Editor)

1. Type `(` at the end of this line: a `)` appears after the cursor →
2. Type `**` here: a `**` pair grows around the cursor →
3. Press Return at the end of this item: a `4.` item appears →
- [ ] Press Return at the end of this task: a new `[ ]` item appears →
- Press Return twice on an empty item: the list ends →

> Press Return at the end of this quote: the `>` prefix continues →

Type three backticks and Return on the empty line below to get a fenced block:

*Expect:* auto-pairing, list and quote continuation, and fence creation as
described in README; ⌘Z undoes each step.
