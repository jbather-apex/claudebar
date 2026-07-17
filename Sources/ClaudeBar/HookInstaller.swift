import Foundation

/// Installs ClaudeBar's hook entries into ~/.claude/settings.json.
/// Merge-only: existing hooks and all other settings are preserved; a backup
/// is written to settings.json.claudebar-bak before any change.
enum HookInstaller {
    static let marker = "ClaudeBar/events.jsonl"

    private static let eventsPath = "$HOME/Library/Application Support/ClaudeBar/events.jsonl"

    private static func command(kind: String) -> String {
        "/usr/bin/jq -c '. + {cb_kind:\"\(kind)\", cb_ts: now}' >> \"\(eventsPath)\""
    }

    /// event name -> (matcher, cb_kind)
    private static let entries: [(event: String, matcher: String, kind: String)] = [
        ("Notification", "permission_prompt", "permission"),
        ("Notification", "idle_prompt|agent_needs_input|elicitation_dialog", "input"),
        ("Stop", "*", "stop"),
        ("SessionStart", "*", "start"),
        ("SessionEnd", "*", "end"),
    ]

    static func isInstalled() -> Bool {
        guard let settings = readSettings(),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        for entry in entries {
            guard let matchers = hooks[entry.event] as? [[String: Any]],
                  matchers.contains(where: { containsMarker($0) })
            else { return false }
        }
        return true
    }

    static func install() throws {
        var settings = readSettings() ?? [:]

        // Backup before touching anything.
        let backupURL = Paths.claudeDir.appendingPathComponent("settings.json.claudebar-bak")
        if FileManager.default.fileExists(atPath: Paths.settingsFile.path) {
            let original = try Data(contentsOf: Paths.settingsFile)
            try original.write(to: backupURL)
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for entry in entries {
            var matchers = hooks[entry.event] as? [[String: Any]] ?? []
            // Skip if an equivalent ClaudeBar entry with this cb_kind already exists.
            let kindMarker = "cb_kind:\"\(entry.kind)\""
            let already = matchers.contains { matcher in
                containsMarker(matcher) && (hookCommands(of: matcher).contains { $0.contains(kindMarker) })
            }
            if already { continue }
            matchers.append([
                "matcher": entry.matcher,
                "hooks": [[
                    "type": "command",
                    "command": command(kind: entry.kind),
                    "async": true,
                    "timeout": 5,
                ]],
            ])
            hooks[entry.event] = matchers
        }
        settings["hooks"] = hooks

        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Paths.settingsFile)

        // Make sure the events file exists so hooks and the tailer line up.
        try FileManager.default.createDirectory(
            at: Paths.appSupportDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: Paths.eventsFile.path) {
            FileManager.default.createFile(atPath: Paths.eventsFile.path, contents: nil)
        }
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: Paths.settingsFile) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func hookCommands(of matcher: [String: Any]) -> [String] {
        ((matcher["hooks"] as? [[String: Any]]) ?? [])
            .compactMap { $0["command"] as? String }
    }

    private static func containsMarker(_ matcher: [String: Any]) -> Bool {
        hookCommands(of: matcher).contains { $0.contains(marker) }
    }
}
