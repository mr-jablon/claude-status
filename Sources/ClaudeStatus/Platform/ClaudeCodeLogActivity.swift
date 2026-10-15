import ClaudeStatusCore
import Foundation

/// Estimates today's share of the weekly window from Claude Code's local transcripts
/// (`~/.claude/projects/**/*.jsonl`). Counts input, cache-creation and output tokens per
/// message; the logs hold tokens, not limit percentages, so the result is only a ratio.
struct ClaudeCodeLogActivity: ActivityEstimating {
    var root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")

    func todayShare(windowStart: Date, dayStart: Date, until: Date) async -> Double? {
        await Task.detached(priority: .utility) { scan(windowStart: windowStart, dayStart: dayStart, until: until) }.value
    }

    private func scan(windowStart: Date, dayStart: Date, until: Date) -> Double? {
        let fm = FileManager.default
        guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        // A streamed message is logged several times with the same id; the last entry is complete.
        var latest: [String: (at: Date, tokens: Double)] = [:]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for case let url as URL in files where url.pathExtension == "jsonl" {
            guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  modified >= windowStart, let data = try? Data(contentsOf: url) else { continue }
            for line in data.split(separator: UInt8(ascii: "\n")) {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let stamp = object["timestamp"] as? String, let at = iso.date(from: stamp),
                      at >= windowStart, at <= until,
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }
                let tokens = ["input_tokens", "cache_creation_input_tokens", "output_tokens"]
                    .reduce(0.0) { $0 + ((usage[$1] as? NSNumber)?.doubleValue ?? 0) }
                let id = (message["id"] as? String) ?? UUID().uuidString
                latest[id] = (at, tokens)
            }
        }
        let total = latest.values.reduce(0) { $0 + $1.tokens }
        guard total > 0 else { return nil }
        let today = latest.values.filter { $0.at >= dayStart }.reduce(0) { $0 + $1.tokens }
        return today / total
    }
}
