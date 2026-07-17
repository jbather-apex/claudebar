import Foundation

/// Reads ~/.claude/sessions/*.json and returns records whose PID is alive.
enum SessionsDirPoller {
    static func poll() -> [SessionFileRecord] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Paths.sessionsDir, includingPropertiesForKeys: nil
        ) else { return [] }

        var records: [SessionFileRecord] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(SessionFileRecord.self, from: data)
            else { continue }
            if isAlive(pid: record.pid) {
                records.append(record)
            }
        }
        return records
    }

    static func isAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
