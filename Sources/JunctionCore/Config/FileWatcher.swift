import Foundation

#if canImport(Darwin)

/// Watches a single file for writes/renames/deletes using a DispatchSource.
/// Editors that atomically replace files (vim, VS Code) delete+rename, so on
/// such events we re-arm on the new inode after a short debounce.
public final class FileWatcher {
    private let url: URL
    private let queue = DispatchQueue(label: "com.jnahian.junction.filewatcher")
    private let debounce: TimeInterval
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var pending: DispatchWorkItem?
    private let handler: () -> Void

    public init(url: URL, debounce: TimeInterval = 0.2, handler: @escaping () -> Void) {
        self.url = url
        self.debounce = debounce
        self.handler = handler
    }

    deinit {
        // Synchronous teardown: an async { [weak self] } here would never run
        // (self is already gone), leaking the source and its file descriptor.
        pending?.cancel()
        source?.cancel() // cancel handler closes the fd
    }

    public func start() {
        queue.async { [weak self] in self?.arm() }
    }

    public func stop() {
        queue.async { [weak self] in self?.disarm() }
    }

    private func arm() {
        disarm()
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File may not exist yet — retry shortly.
            queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.arm() }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let events = src.data
            self.fire()
            if events.contains(.rename) || events.contains(.delete) {
                // Atomic replace: watch the new file.
                self.queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.arm() }
            }
        }
        src.setCancelHandler { [fd] in
            if fd >= 0 { close(fd) }
        }
        source = src
        src.resume()
    }

    private func disarm() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
        fd = -1
    }

    private func fire() {
        pending?.cancel()
        let work = DispatchWorkItem { [handler] in
            DispatchQueue.main.async { handler() }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}

#else

/// No-op stub so JunctionCore compiles on Linux (CI runs the engine tests there).
public final class FileWatcher {
    public init(url: URL, debounce: TimeInterval = 0.2, handler: @escaping () -> Void) {}
    public func start() {}
    public func stop() {}
}

#endif
