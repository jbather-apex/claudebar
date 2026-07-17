import Foundation

/// Tails events.jsonl (appended to by Claude Code hooks) and delivers each new
/// line as a HookEvent on the main queue. Uses a DispatchSource vnode watcher;
/// the file is created up front so the watcher can always attach.
final class HookEventTailer {
    private var offset: UInt64 = 0
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private let onEvent: (HookEvent) -> Void
    private var partialLine = Data()

    init(onEvent: @escaping (HookEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start() {
        try? FileManager.default.createDirectory(
            at: Paths.appSupportDir, withIntermediateDirectories: true)
        let path = Paths.eventsFile.path
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        // Start from the end of the file: history was already reconciled via
        // the sessions dir; only new events matter.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64 {
            offset = size
        }
        attach()
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func attach() {
        fd = open(Paths.eventsFile.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility))
        src.setEventHandler { [weak self] in
            guard let self else { return }
            if src.data.contains(.delete) || src.data.contains(.rename) {
                src.cancel()
                self.offset = 0
                self.partialLine.removeAll()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
                    self.start()
                }
                return
            }
            self.drain()
        }
        src.setCancelHandler { [fd = self.fd] in close(fd) }
        source = src
        src.resume()
        drain()
    }

    private func drain() {
        guard let handle = try? FileHandle(forReadingFrom: Paths.eventsFile) else { return }
        defer { try? handle.close() }
        // If the file was truncated, restart from the beginning.
        let end = (try? handle.seekToEnd()) ?? 0
        if end < offset { offset = 0; partialLine.removeAll() }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        offset += UInt64(data.count)

        var buffer = partialLine
        buffer.append(data)
        var lines = buffer.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        // Keep a trailing partial line (no newline yet) for the next drain.
        if buffer.last != UInt8(ascii: "\n"), let last = lines.popLast() {
            partialLine = Data(last)
        } else {
            partialLine.removeAll()
        }

        let decoder = JSONDecoder()
        for line in lines {
            guard let event = try? decoder.decode(HookEvent.self, from: Data(line)) else { continue }
            DispatchQueue.main.async { [onEvent] in onEvent(event) }
        }
    }
}
