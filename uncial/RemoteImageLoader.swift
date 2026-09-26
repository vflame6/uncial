import AppKit
import ImageIO

/// Fetches the http(s) pictures Live Preview draws, within bounds: its own ephemeral session with a
/// time budget per picture, `image/*` responses only, at most `maxBytes` of them, and decoding
/// downsampled to `maxPixelSize`, so a small file declaring huge dimensions does not become a huge
/// bitmap either. The shared session it replaces (STAB-6, 2026-09-26) read any destination whole into
/// memory: a 600 MB response took the app to 1.25 GB, and an endless one ran for its 7-day timeout.
nonisolated final class RemoteImageLoader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = RemoteImageLoader()

    let maxBytes: Int
    let maxPixelSize: Int
    /// The session's delegate queue; `loads` belongs to it.
    private let queue = OperationQueue()
    private var session: URLSession!
    private var loads: [Int: Load] = [:]

    private struct Load {
        var data = Data()
        let completion: (NSImage?) -> Void
    }

    /// Live Preview fits a picture into the text column (720 pt at most) and 480 pt of height, drawn
    /// at twice that on a Retina screen: 2048 pixels are plenty.
    init(maxBytes: Int = 20 << 20, timeout: TimeInterval = 30, maxPixelSize: Int = 2048) {
        self.maxBytes = maxBytes
        self.maxPixelSize = maxPixelSize
        queue.maxConcurrentOperationCount = 1
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    /// Calls back on the main thread with the picture, or with nil for anything that is not one or
    /// does not fit the budget.
    func load(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        queue.addOperation {
            let task = self.session.dataTask(with: url)
            self.loads[task.taskIdentifier] = Load(completion: completion)
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        // URLSession's type, sniffed from the bytes when the server says text/plain or
        // application/octet-stream, so a mislabeled picture still counts; a page does not.
        let isPicture = response.mimeType?.lowercased().hasPrefix("image/") ?? false
        // -1 when the server does not say.
        let fits = response.expectedContentLength <= Int64(maxBytes)
        completionHandler((200..<300).contains(status) && isPicture && fits ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        loads[dataTask.taskIdentifier]?.data.append(data)
        if (loads[dataTask.taskIdentifier]?.data.count ?? 0) > maxBytes {
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let load = loads.removeValue(forKey: task.taskIdentifier) else { return }
        let image = error == nil ? Self.image(from: load.data, maxPixelSize: maxPixelSize) : nil
        DispatchQueue.main.async { load.completion(image) }
    }

    /// The picture in `data`, its bitmap at most `maxPixelSize` on either side, at the size in points
    /// `NSImage(data:)` would give it (the pixels at the file's resolution, turned upright). What ImageIO
    /// does not read as a bitmap (SVG) goes to `NSImage(data:)`, drawn as a vector.
    static func image(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return NSImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let dpiWidth = (properties[kCGImagePropertyDPIWidth] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
        let dpiHeight = (properties[kCGImagePropertyDPIHeight] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? 72
        var size = NSSize(width: Double(width) * 72 / dpiWidth, height: Double(height) * 72 / dpiHeight)
        // Orientations 5 to 8 swap width and height.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
            size = NSSize(width: size.height, height: size.width)
        }
        return NSImage(cgImage: bitmap, size: size)
    }
}
