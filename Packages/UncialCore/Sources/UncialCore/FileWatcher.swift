import Foundation

/// Watches one file for content changes, surviving atomic saves (write-to-temp + rename).
public final class FileWatcher: @unchecked Sendable {
    public typealias ChangeHandler = @MainActor @Sendable () -> Void

    private let url: URL
    private let debounce: TimeInterval
    private let onChange: ChangeHandler
    private let queue = DispatchQueue(label: "com.maksimradaev.uncial.filewatcher")
    private var source: DispatchSourceFileSystemObject?
    private var pendingChange: DispatchWorkItem?
    private var reopenAttempts = 0
    private var isRunning = false

    private static let maxReopenAttempts = 20
    private static let reopenInterval: TimeInterval = 0.05

    public init(url: URL, debounce: TimeInterval = 0.1, onChange: @escaping ChangeHandler) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
    }

    deinit {
        source?.cancel()
        pendingChange?.cancel()
    }

    public func start() {
        queue.async {
            guard !self.isRunning else { return }
            self.isRunning = true
            self.reopenAttempts = 0
            if !self.arm() { self.scheduleReopen() }
        }
    }

    public func stop() {
        queue.async {
            self.isRunning = false
            self.disarm()
            self.pendingChange?.cancel()
            self.pendingChange = nil
        }
    }

    // MARK: - Queue-confined

    /// Opens the file and installs a vnode source. Returns false when the file can't be opened.
    private func arm() -> Bool {
        disarm()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.handleEvent() }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.activate()
        return true
    }

    private func disarm() {
        source?.cancel()
        source = nil
    }

    private func handleEvent() {
        guard let source else { return }
        let flags = source.data
        if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
            // The path now points at a new inode (atomic save) or nothing; re-arm on the path.
            disarm()
            reopenAttempts = 0
            scheduleReopen()
        } else {
            scheduleChange()
        }
    }

    private func scheduleReopen() {
        guard isRunning, reopenAttempts < Self.maxReopenAttempts else { return }
        reopenAttempts += 1
        queue.asyncAfter(deadline: .now() + Self.reopenInterval) { [weak self] in
            guard let self, self.isRunning else { return }
            if self.arm() {
                self.reopenAttempts = 0
                self.scheduleChange()
            } else {
                self.scheduleReopen()
            }
        }
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        let onChange = self.onChange
        let work = DispatchWorkItem {
            Task { @MainActor in onChange() }
        }
        pendingChange = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
