import Foundation

/// Extracts the AI-generated session title (`{"type":"ai-title","aiTitle":...}`
/// lines) from a session transcript. Transcripts can be tens of MB, so only the
/// head and tail of the file are scanned; the latest match wins.
enum TranscriptTitles {
    private static let chunkSize = 256 * 1024

    static func title(cwd: String, sessionId: String) -> String? {
        let url = Paths.transcript(cwd: cwd, sessionId: sessionId)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0

        var chunks: [Data] = []
        try? handle.seek(toOffset: 0)
        if let head = try? handle.read(upToCount: chunkSize) { chunks.append(head) }
        if size > UInt64(chunkSize) {
            let tailStart = size - UInt64(min(UInt64(chunkSize), size))
            try? handle.seek(toOffset: tailStart)
            if let tail = try? handle.readToEnd() { chunks.append(tail) }
        }

        var latest: String?
        let decoder = JSONDecoder()
        struct TitleLine: Decodable { let type: String; let aiTitle: String? }
        for chunk in chunks {
            for line in chunk.split(separator: UInt8(ascii: "\n")) {
                // Cheap pre-filter before JSON-decoding the line.
                guard line.count < 4096,
                      line.range(of: Data(#""type":"ai-title""#.utf8)) != nil,
                      let parsed = try? decoder.decode(TitleLine.self, from: Data(line)),
                      parsed.type == "ai-title",
                      let title = parsed.aiTitle
                else { continue }
                latest = title
            }
        }
        return latest
    }
}
