import Foundation

enum Paths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var claudeDir: URL { home.appendingPathComponent(".claude") }
    static var sessionsDir: URL { claudeDir.appendingPathComponent("sessions") }
    static var projectsDir: URL { claudeDir.appendingPathComponent("projects") }
    static var settingsFile: URL { claudeDir.appendingPathComponent("settings.json") }

    static var appSupportDir: URL {
        home.appendingPathComponent("Library/Application Support/ClaudeBar")
    }
    static var eventsFile: URL { appSupportDir.appendingPathComponent("events.jsonl") }

    /// Transcript path for a session: ~/.claude/projects/<slugified-cwd>/<sessionId>.jsonl
    /// Claude Code slugifies the cwd by replacing non-alphanumeric chars with "-".
    static func transcript(cwd: String, sessionId: String) -> URL {
        let slug = String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        return projectsDir
            .appendingPathComponent(slug)
            .appendingPathComponent(sessionId + ".jsonl")
    }
}
