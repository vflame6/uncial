import AppKit
import Testing
@testable import Uncial

@MainActor
@Suite struct LocalPicturesTests {
    private let folder = TemporaryDirectory()

    /// A PNG of `width` × `height` pixels that says it has `dpi` of them to the inch.
    private func png(_ name: String, width: Int, height: Int, dpi: CGFloat = 72) throws -> URL {
        let rep = bitmap(width: width, height: height, background: .systemTeal, flipped: false) { _ in }
        rep.size = NSSize(width: CGFloat(width) * 72 / dpi, height: CGFloat(height) * 72 / dpi)
        return try folder.file(name, rep.representation(using: .png, properties: [:])!)
    }

    private func pixels(_ picture: NSImage) -> NSSize? {
        picture.representations.first.map { NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) }
    }

    /// The size is there at once, read from the file's header, since the layout needs it; the bitmap
    /// comes a moment later, decoded off the main thread. Decoding a screenshot when it first scrolled
    /// into view held the main thread for two frames and more.
    @Test func givesTheSizeAtOnceAndTheBitmapLater() async throws {
        let url = try png("a.png", width: 400, height: 300)
        let pictures = LocalPictures()
        var loads = 0
        pictures.onLoad = { loads += 1 }
        let picture = try #require(pictures.picture(at: url))
        #expect(picture.size == NSSize(width: 400, height: 300))
        #expect(picture.representations.isEmpty)
        await eventually { !picture.representations.isEmpty }
        #expect(pixels(picture) == NSSize(width: 400, height: 300))
        #expect(loads == 1)
        #expect(pictures.picture(at: url) === picture)
    }

    /// A screenshot from a Retina screen takes its size in points, and its bitmap is no larger than
    /// Live Preview draws it (480 points high at most, at the screen's scale).
    @Test func keepsBitmapsAtTheSizeTheyAreDrawn() async throws {
        let url = try png("shot.png", width: 2880, height: 1800, dpi: 144)
        let pictures = LocalPictures(scale: 2)
        let picture = try #require(pictures.picture(at: url))
        #expect(picture.size == NSSize(width: 1440, height: 900))
        await eventually { !picture.representations.isEmpty }
        #expect(pixels(picture) == NSSize(width: 1536, height: 960))
        #expect(picture.representations.first?.size == NSSize(width: 1440, height: 900))
    }

    /// Bitmaps are decoded ahead while they fit the budget; past it a picture gets its bitmap when it is
    /// drawn, and one that was not drawn lately gives its own up.
    @Test func keepsWithinItsBudget() async throws {
        // 960 × 480 pixels each once decoded: 1.8 MB.
        let urls = try (1...4).map { try png("p\($0).png", width: 1000, height: 500) }
        let pictures = LocalPictures(budget: 4_000_000, scale: 1)
        let all = try urls.map { try #require(pictures.picture(at: $0)) }
        await eventually { !all[0].representations.isEmpty && !all[1].representations.isEmpty }
        #expect(pixels(all[0]) == NSSize(width: 960, height: 480))
        try await Task.sleep(for: .milliseconds(150))
        #expect(all[2].representations.isEmpty && all[3].representations.isEmpty)
        pictures.willDraw(all[0])
        pictures.willDraw(all[3])
        await eventually { !all[3].representations.isEmpty }
        #expect(!all[3].representations.isEmpty && !all[0].representations.isEmpty)
        #expect(all[1].representations.isEmpty)
        // Drawn again, it comes back.
        pictures.willDraw(all[1])
        await eventually { !all[1].representations.isEmpty }
        #expect(!all[1].representations.isEmpty)
    }

    /// A file that is no picture, or is not there, gives none; a vector picture is drawn as it is.
    @Test func leavesOutWhatIsNoBitmap() throws {
        let pictures = LocalPictures()
        #expect(pictures.picture(at: folder.url("missing.png")) == nil)
        #expect(pictures.picture(at: try folder.file("notes.png", "not a picture")) == nil)
        let svg = try folder.file("dot.svg", #"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><circle cx="10" cy="10" r="5"/></svg>"#)
        let vector = try #require(pictures.picture(at: svg))
        #expect(vector.size == NSSize(width: 40, height: 20) && !vector.representations.isEmpty)
    }

    /// A picture gets its own file's bitmap, whatever was being decoded for pictures forgotten since:
    /// a decode that finished after `removeAll()` was matched by the address of its picture, which a
    /// later picture can have, and put one file's bitmap under another's name.
    @Test func picturesForgottenWhileDecodingLeaveTheNewOnesAlone() async throws {
        // Twelve files, each one flat color of its own.
        let colors = (0..<12).map { NSColor(srgbRed: CGFloat($0) / 12, green: 0.25, blue: 0.5, alpha: 1) }
        let urls = try colors.enumerated().map { index, color in
            try folder.file("c\(index).png", bitmap(width: 600, height: 400, background: color, flipped: false) { _ in }.representation(using: .png, properties: [:])!)
        }
        let pictures = LocalPictures(scale: 1)
        // Two generations asked for and forgotten before their bitmaps are there, then a third.
        for _ in 1...2 {
            autoreleasepool { _ = urls.map { pictures.picture(at: $0) } }
            pictures.removeAll()
        }
        let last = try urls.map { try #require(pictures.picture(at: $0)) }
        await eventually(within: 5) { last.allSatisfy { !$0.representations.isEmpty } }
        try await Task.sleep(for: .milliseconds(200))
        func red(_ rep: NSBitmapImageRep?) -> CGFloat? { rep?.colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB)?.redComponent }
        for (index, picture) in last.enumerated() {
            // The file's own color, decoded the same way.
            let source = try #require(CGImageSourceCreateWithURL(urls[index] as CFURL, nil))
            let own = try #require(red(RemoteImageLoader.bitmap(from: source, maxPixelSize: 600).map(NSBitmapImageRep.init(cgImage:))))
            let shown = try #require(red(picture.representations.first as? NSBitmapImageRep), "picture \(index) has no bitmap")
            #expect(abs(shown - own) < 0.005, "picture \(index) shows another file's bitmap (red \(shown), its own is \(own))")
        }
    }
}
