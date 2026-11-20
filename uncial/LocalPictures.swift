import AppKit
import ImageIO

/// The pictures Live Preview draws from image files. A picture's size is there at once, read from the
/// file's header, because the layout needs it; its bitmap comes from a background queue, no larger than
/// it is drawn. The file used to be decoded whole, on the main thread, when the picture first scrolled
/// into view: two frames and more for a screenshot, at every picture, and 20 MB kept for each.
///
/// Bitmaps are decoded ahead, in the order the pictures are asked for (the document's), while they fit
/// `budget`. Past it a picture gets its bitmap when it is drawn, and one that was not drawn lately gives
/// its own up. An image without a bitmap draws nothing: `InlineLayoutManager` leaves its room empty.
final class LocalPictures {
    /// Called on the main thread when a bitmap has arrived, for the views to draw again.
    var onLoad: (() -> Void)?

    private enum State {
        case empty, decoding, ready, failed
    }

    private struct Entry {
        let image: NSImage
        let url: URL
        let maxPixelSize: Int
        /// What the bitmap takes once decoded.
        let bytes: Int
        /// Tells this picture from one that was at the same address before it: a decode outlives
        /// `removeAll()`, and a later picture can get the address of the one it was started for.
        let serial: Int
        var state = State.empty
        var lastDrawn: CFAbsoluteTime = 0
    }

    private let budget: Int
    private let scale: CGFloat
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var images: [URL: NSImage] = [:]
    /// Bytes of the bitmaps decoded or being decoded.
    private var held = 0
    private var serial = 0

    /// Decoding is a few at a time: it competes with the editor for the processor.
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 3
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// A picture drawn within this long keeps its bitmap whatever the budget says.
    private static let recently: CFAbsoluteTime = 2

    /// `scale` is the pixels per point the bitmaps are kept for: the sharpest screen's unless given.
    init(budget: Int = 256 << 20, scale: CGFloat? = nil) {
        self.budget = budget
        self.scale = scale ?? NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }

    /// The picture in the file at `url`, the same one every time: its size is set, its bitmap arrives
    /// later. A vector picture (SVG, PDF) is NSImage's own, drawn as it is. Nil when the file is no picture.
    func picture(at url: URL) -> NSImage? {
        if let image = images[url] { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            let vector = NSImage(contentsOf: url).flatMap { $0.isValid ? $0 : nil }
            images[url] = vector
            return vector
        }
        let size = RemoteImageLoader.size(pixelWidth: width, pixelHeight: height, properties: properties)
        // As large as it is ever drawn: the height Live Preview stops at, a width no column has.
        let drawn = min(1, InlineStyle.maximumImageHeight / size.height, Self.widestColumn / size.width)
        let turned = (properties[kCGImagePropertyOrientation] as? Int).map { (5...8).contains($0) } ?? false
        let upright = turned ? NSSize(width: height, height: width) : NSSize(width: width, height: height)
        let kept = min(1, size.width * drawn * scale / upright.width, size.height * drawn * scale / upright.height)
        let pixels = NSSize(width: (upright.width * kept).rounded(.up), height: (upright.height * kept).rounded(.up))
        let image = NSImage(size: size)
        serial += 1
        entries[ObjectIdentifier(image)] = Entry(image: image, url: url, maxPixelSize: Int(max(pixels.width, pixels.height)),
                                                 bytes: Int(pixels.width * pixels.height) * 4, serial: serial)
        images[url] = image
        if held + Int(pixels.width * pixels.height) * 4 <= budget {
            decode(ObjectIdentifier(image))
        }
        return image
    }

    /// No text column is wider than this, in points.
    private static let widestColumn: CGFloat = 2048

    /// `image` is about to be drawn: it gets its bitmap if it has none, and keeps it for now.
    func willDraw(_ image: NSImage) {
        let id = ObjectIdentifier(image)
        guard entries[id] != nil else { return }
        entries[id]?.lastDrawn = CFAbsoluteTimeGetCurrent()
        if entries[id]?.state == .empty {
            decode(id)
            makeRoom()
        }
    }

    /// Forgets every picture: the same path may name another file now. What waits to be decoded for
    /// them is dropped.
    func removeAll() {
        queue.cancelAllOperations()
        entries.removeAll()
        images.removeAll()
        held = 0
    }

    private func decode(_ id: ObjectIdentifier) {
        guard let entry = entries[id], entry.state == .empty else { return }
        entries[id]?.state = .decoding
        held += entry.bytes
        let url = entry.url
        let maxPixelSize = entry.maxPixelSize
        let serial = entry.serial
        queue.addOperation { [weak self] in
            let bitmap = Self.bitmap(at: url, maxPixelSize: maxPixelSize)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finish(id, serial, with: bitmap) }
            }
        }
    }

    nonisolated private static func bitmap(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return RemoteImageLoader.bitmap(from: source, maxPixelSize: maxPixelSize)
    }

    private func finish(_ id: ObjectIdentifier, _ serial: Int, with bitmap: CGImage?) {
        // Forgotten meanwhile: `removeAll()` took its bytes off the count.
        guard let entry = entries[id], entry.serial == serial, entry.state == .decoding else { return }
        guard let bitmap else {
            entries[id]?.state = .failed
            held -= entry.bytes
            return
        }
        let representation = NSBitmapImageRep(cgImage: bitmap)
        representation.size = entry.image.size
        entry.image.addRepresentation(representation)
        entries[id]?.state = .ready
        makeRoom()
        onLoad?()
    }

    /// Over the budget, the pictures drawn longest ago (or never) give up their bitmaps, but none
    /// that was drawn a moment ago.
    private func makeRoom() {
        guard held > budget else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let idle = entries.filter { $0.value.state == .ready && now - $0.value.lastDrawn > Self.recently }
            .sorted { $0.value.lastDrawn < $1.value.lastDrawn }
        for (id, entry) in idle {
            guard held > budget else { break }
            entry.image.representations.forEach(entry.image.removeRepresentation)
            entries[id]?.state = .empty
            held -= entry.bytes
        }
    }
}
