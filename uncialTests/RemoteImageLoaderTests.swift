import AppKit
import Testing
@testable import Uncial

/// Live Preview's web pictures come from a server the document names, not the user: the loader takes
/// pictures only, and only within a size and a time budget.
@Suite(.serialized) struct RemoteImageLoaderTests {
    private static let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    private func server(_ routes: [String: LoopbackHTTPServer.Reply]) async throws -> LoopbackHTTPServer {
        let server = try LoopbackHTTPServer(routes: routes)
        await server.start()
        return server
    }

    private func load(_ url: URL, with loader: RemoteImageLoader) async -> NSImage? {
        await withCheckedContinuation { continuation in
            loader.load(url) { continuation.resume(returning: $0) }
        }
    }

    @Test func loadsAPicture() async throws {
        let server = try await server(["/pixel.png": .body(contentType: "image/png", Self.pixel)])
        defer { server.stop() }
        let image = await load(server.url("/pixel.png"), with: RemoteImageLoader())
        #expect(image?.size == NSSize(width: 1, height: 1))
    }

    @Test func refusesWhatIsNotAPicture() async throws {
        let server = try await server(["/page": .body(contentType: "text/html", Data("<html></html>".utf8))])
        defer { server.stop() }
        #expect(await load(server.url("/page"), with: RemoteImageLoader()) == nil)
        #expect(await load(server.url("/missing.png"), with: RemoteImageLoader()) == nil)
    }

    /// An endless response is cut off at the cap, not read into memory for as long as it lasts.
    @Test func stopsAtTheSizeCap() async throws {
        let chunk = Data(repeating: 0x55, count: 64 << 10)
        let server = try await server(["/endless.png": .stream(contentType: "image/png", chunk: chunk, total: nil, declaredLength: nil)])
        defer { server.stop() }
        let start = ContinuousClock.now
        #expect(await load(server.url("/endless.png"), with: RemoteImageLoader(maxBytes: 1 << 20)) == nil)
        #expect(ContinuousClock.now - start < .seconds(10))
        #expect(server.sent("/endless.png") < 16 << 20)
    }

    /// A picture announced as larger than the cap is not fetched at all.
    @Test func refusesADeclaredOversize() async throws {
        let chunk = Data(repeating: 0x55, count: 64 << 10)
        let server = try await server(["/huge.png": .stream(contentType: "image/png", chunk: chunk, total: 50 << 20, declaredLength: 50 << 20)])
        defer { server.stop() }
        #expect(await load(server.url("/huge.png"), with: RemoteImageLoader(maxBytes: 1 << 20)) == nil)
        #expect(server.sent("/huge.png") < 16 << 20)
    }

    /// A server that stops sending gets the time budget, not the shared session's seven days.
    @Test func givesUpOnAStall() async throws {
        let server = try await server(["/stall.png": .stall(contentType: "image/png", bytes: Self.pixel.prefix(20))])
        defer { server.stop() }
        let start = ContinuousClock.now
        #expect(await load(server.url("/stall.png"), with: RemoteImageLoader(timeout: 1)) == nil)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    /// A large picture is decoded at most `maxPixelSize` wide, and keeps its size in points.
    @Test func downsamplesLargePictures() async throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3000, pixelsHigh: 1000, bitsPerSample: 8,
                                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                   bytesPerRow: 0, bitsPerPixel: 0))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let server = try await server(["/wide.png": .body(contentType: "image/png", png)])
        defer { server.stop() }
        let image = try #require(await load(server.url("/wide.png"), with: RemoteImageLoader(maxPixelSize: 512)))
        #expect(image.size == NSSize(width: 3000, height: 1000))
        let drawn = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(drawn.width <= 512 && drawn.height <= 512)
    }
}
