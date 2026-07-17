import Foundation
import AppKit

/// Focuses the terminal window/tab hosting a Claude process, by matching the
/// process's controlling tty against iTerm2 / Terminal.app sessions.
/// Best-effort: falls back to activating the ancestor terminal app.
enum TerminalJumper {
    static func jump(toPid pid: Int32) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let tty = tty(ofPid: pid) else {
                activateAncestorApp(ofPid: pid)
                return
            }
            // Inside tmux, `tty` is the pane's pty — switch tmux to that pane
            // and then focus the terminal tab hosting the tmux client instead.
            if jumpTmux(paneTty: tty) { return }
            if focusTerminalTab(tty: tty) { return }
            activateAncestorApp(ofPid: pid)
        }
    }

    private static func focusTerminalTab(tty: String) -> Bool {
        if isRunning(bundleId: "com.googlecode.iterm2"), jumpITerm(tty: tty) { return true }
        if isRunning(bundleId: "com.apple.Terminal"), jumpTerminal(tty: tty) { return true }
        return false
    }

    // MARK: - tmux

    private static func tmuxBin() -> String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// If `paneTty` belongs to a tmux pane: select its window+pane, point a
    /// client at its session if none is, and focus the terminal tab running
    /// that client. Returns false when the tty is not a tmux pane.
    private static func jumpTmux(paneTty: String) -> Bool {
        guard let tmux = tmuxBin(),
              let panes = run(tmux, ["list-panes", "-a", "-F",
                                     "#{pane_tty}|#{session_name}|#{window_index}|#{pane_id}"])
        else { return false }
        guard let paneLine = panes.split(separator: "\n")
            .first(where: { $0.hasPrefix(paneTty + "|") })
        else { return false }
        let parts = paneLine.split(separator: "|").map(String.init)
        guard parts.count >= 4 else { return false }
        let session = parts[1], window = parts[2], paneId = parts[3]

        _ = run(tmux, ["select-window", "-t", "\(session):\(window)"])
        _ = run(tmux, ["select-pane", "-t", paneId])

        // Find a client showing this session; retarget the first client if none is.
        var clientTty: String?
        if let clients = run(tmux, ["list-clients", "-F", "#{client_tty}|#{session_name}"]) {
            let lines = clients.split(separator: "\n").map(String.init)
            if let attached = lines.first(where: { $0.hasSuffix("|" + session) }) {
                clientTty = String(attached.split(separator: "|")[0])
            } else if let first = lines.first {
                let ctty = String(first.split(separator: "|")[0])
                _ = run(tmux, ["switch-client", "-c", ctty, "-t", session])
                clientTty = ctty
            }
        }
        if let clientTty {
            _ = focusTerminalTab(tty: clientTty)
        }
        return true
    }

    /// `ps -o tty= -p PID` → "/dev/ttys012"
    static func tty(ofPid pid: Int32) -> String? {
        let out = run("/bin/ps", ["-o", "tty=", "-p", String(pid)])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let out, !out.isEmpty, out != "??" else { return nil }
        return "/dev/" + out
    }

    private static func isRunning(bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    private static func jumpITerm(tty: String) -> Bool {
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select w
                            tell t to select
                            tell s to select
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "notfound"
        """
        return runAppleScript(script) == "ok"
    }

    private static func jumpTerminal(tty: String) -> Bool {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell
        return "notfound"
        """
        return runAppleScript(script) == "ok"
    }

    /// Walk the process ancestry looking for a known terminal app and activate it.
    private static func activateAncestorApp(ofPid pid: Int32) {
        var current = pid
        for _ in 0..<10 {
            guard let ppidStr = run("/bin/ps", ["-o", "ppid=", "-p", String(current)])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                let ppid = Int32(ppidStr), ppid > 1
            else { break }
            if let app = NSRunningApplication(processIdentifier: ppid),
               app.bundleIdentifier != nil, app.activationPolicy == .regular {
                DispatchQueue.main.async { app.activate() }
                return
            }
            current = ppid
        }
    }

    private static func runAppleScript(_ source: String) -> String? {
        // osascript (not NSAppleScript) so Automation prompts attribute correctly
        // and errors are non-fatal.
        run("/usr/bin/osascript", ["-e", source])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
