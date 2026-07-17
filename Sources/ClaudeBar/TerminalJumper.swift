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
            if isRunning(bundleId: "com.googlecode.iterm2"), jumpITerm(tty: tty) { return }
            if isRunning(bundleId: "com.apple.Terminal"), jumpTerminal(tty: tty) { return }
            activateAncestorApp(ofPid: pid)
        }
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
