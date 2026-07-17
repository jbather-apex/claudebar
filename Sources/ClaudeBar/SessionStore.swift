import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var hooksInstalled: Bool = false

    var attentionCount: Int { sessions.filter { $0.state.needsAttention }.count }

    /// Latest hook-event overlay per sessionId.
    private struct EventState {
        var state: SessionState
        var message: String?
        var timestamp: Date
        var waitingSince: Date?
        var cwd: String?
        var ended: Bool = false
    }

    private var eventStates: [String: EventState] = [:]
    private var titleCache: [String: String] = [:]
    private var titleLastAttempt: [String: Date] = [:]
    private var tailer: HookEventTailer?
    private var pollTimer: Timer?
    private let notifier = Notifier()

    func start() {
        notifier.requestAuthorization()
        let tailer = HookEventTailer { [weak self] event in
            self?.apply(event: event)
        }
        tailer.start()
        self.tailer = tailer

        hooksInstalled = HookInstaller.isInstalled()
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func installHooks() {
        do {
            try HookInstaller.install()
            hooksInstalled = true
        } catch {
            NSLog("ClaudeBar: hook install failed: \(error)")
        }
    }

    // MARK: - Hook events

    private func apply(event: HookEvent) {
        let now = event.timestamp
        var ev = eventStates[event.sessionId]
            ?? EventState(state: .working, message: nil, timestamp: now, waitingSince: nil, cwd: event.cwd)
        ev.timestamp = now
        if let cwd = event.cwd { ev.cwd = cwd }

        switch event.cbKind {
        case "permission":
            ev.state = .needsPermission
            ev.message = event.message
            ev.waitingSince = now
        case "input":
            ev.state = .needsInput
            ev.message = event.message
            ev.waitingSince = now
        case "stop":
            ev.state = .idle
            ev.message = nil
            ev.waitingSince = nil
        case "start":
            ev.state = .working
            ev.message = nil
            ev.waitingSince = nil
            ev.ended = false
        case "end":
            ev.ended = true
        default:
            break
        }
        eventStates[event.sessionId] = ev
        refresh()

        if ev.state.needsAttention, let session = sessions.first(where: { $0.sessionId == event.sessionId }) {
            notifier.notifyAttention(session: session)
        }
    }

    // MARK: - Reconcile

    func refresh() {
        let records = SessionsDirPoller.poll()
        var next: [ClaudeSession] = []
        var seen = Set<String>()

        for record in records {
            seen.insert(record.sessionId)
            next.append(build(from: record))
        }

        // Sessions known only from hook events (older CLIs / missing session
        // file): keep them until SessionEnd or 30 min of silence.
        for (sessionId, ev) in eventStates where !seen.contains(sessionId) {
            if ev.ended || Date().timeIntervalSince(ev.timestamp) > 1800 {
                eventStates.removeValue(forKey: sessionId)
                continue
            }
            next.append(ClaudeSession(
                sessionId: sessionId,
                pid: nil,
                cwd: ev.cwd ?? "",
                name: "",
                title: cachedTitle(sessionId: sessionId, cwd: ev.cwd ?? ""),
                state: ev.state,
                message: ev.message,
                waitingSince: ev.waitingSince,
                updatedAt: ev.timestamp))
        }

        next.sort { a, b in
            if a.state.needsAttention != b.state.needsAttention {
                return a.state.needsAttention
            }
            return a.updatedAt > b.updatedAt
        }
        sessions = next
    }

    private func build(from record: SessionFileRecord) -> ClaudeSession {
        let fileState = stateFromStatus(record.status)
        let fileStateAt = record.statusUpdatedAtDate ?? .distantPast
        var state = fileState ?? .working
        var message: String?
        var waitingSince: Date?

        if var ev = eventStates[record.sessionId] {
            // A "busy" status newer than the event means the prompt was
            // answered — the event overlay is stale.
            let fileClearsWaiting = fileState == .working
                && fileStateAt > ev.timestamp
            if ev.state.needsAttention && fileClearsWaiting {
                ev.state = .working
                ev.message = nil
                ev.waitingSince = nil
                eventStates[record.sessionId] = ev
            }
            if ev.timestamp >= fileStateAt || fileState == nil {
                state = ev.state
                message = ev.message
                waitingSince = ev.waitingSince
            }
        }

        // Waiting states from the session file itself (newer CLIs write these
        // even without hooks installed).
        if let fileState, fileState.needsAttention, fileStateAt > (waitingSince ?? .distantPast) {
            state = fileState
            waitingSince = waitingSince ?? fileStateAt
        }

        return ClaudeSession(
            sessionId: record.sessionId,
            pid: record.pid,
            cwd: record.cwd,
            name: record.name ?? "",
            title: cachedTitle(sessionId: record.sessionId, cwd: record.cwd),
            state: state,
            message: message,
            waitingSince: waitingSince,
            updatedAt: record.statusUpdatedAtDate ?? Date())
    }

    private func stateFromStatus(_ status: String?) -> SessionState? {
        guard let status = status?.lowercased(), !status.isEmpty else { return nil }
        if status.contains("permission") { return .needsPermission }
        if status.contains("wait") || status.contains("await") || status.contains("blocked") {
            return .needsInput
        }
        switch status {
        case "idle", "ready": return .idle
        case "busy", "running", "thinking": return .working
        default: return .working
        }
    }

    private func cachedTitle(sessionId: String, cwd: String) -> String? {
        if let title = titleCache[sessionId] { return title }
        guard !cwd.isEmpty else { return nil }
        // Retry at most once a minute — the ai-title line appears shortly
        // after the first prompt.
        if let last = titleLastAttempt[sessionId], Date().timeIntervalSince(last) < 60 {
            return nil
        }
        titleLastAttempt[sessionId] = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let title = TranscriptTitles.title(cwd: cwd, sessionId: sessionId)
            guard let title else { return }
            Task { @MainActor in
                self?.titleCache[sessionId] = title
                self?.refresh()
            }
        }
        return nil
    }
}
