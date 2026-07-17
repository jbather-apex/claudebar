import Foundation

enum SessionState: String {
    case working
    case needsPermission
    case needsInput
    case idle

    var needsAttention: Bool {
        self == .needsPermission || self == .needsInput
    }

    var displayName: String {
        switch self {
        case .working: return "working"
        case .needsPermission: return "needs permission"
        case .needsInput: return "needs input"
        case .idle: return "idle"
        }
    }
}

struct ClaudeSession: Identifiable {
    let sessionId: String
    var pid: Int32?
    var cwd: String
    var name: String
    var title: String?
    var state: SessionState
    var message: String?
    var waitingSince: Date?
    var updatedAt: Date

    var id: String { sessionId }

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if !name.isEmpty { return name }
        return (cwd as NSString).lastPathComponent
    }

    var displayCwd: String {
        let home = NSHomeDirectory()
        if cwd.hasPrefix(home) {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }
}

/// One `~/.claude/sessions/<pid>.json` file. Older CLIs omit `status`.
struct SessionFileRecord: Decodable {
    let pid: Int32
    let sessionId: String
    let cwd: String
    let name: String?
    let status: String?
    let kind: String?
    let entrypoint: String?
    let updatedAt: Double?        // epoch ms
    let statusUpdatedAt: Double?  // epoch ms

    var statusUpdatedAtDate: Date? {
        guard let ms = statusUpdatedAt ?? updatedAt else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }
}

/// One line of events.jsonl — a Claude Code hook payload, tagged by the hook
/// command with `cb_kind` (permission | input | stop | start | end) and `cb_ts`.
struct HookEvent: Decodable {
    let sessionId: String
    let hookEventName: String?
    let cwd: String?
    let message: String?
    let lastAssistantMessage: String?
    let cbKind: String?
    let cbTs: Double?  // epoch seconds

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case message
        case lastAssistantMessage = "last_assistant_message"
        case cbKind = "cb_kind"
        case cbTs = "cb_ts"
    }

    var timestamp: Date {
        cbTs.map { Date(timeIntervalSince1970: $0) } ?? Date()
    }
}
