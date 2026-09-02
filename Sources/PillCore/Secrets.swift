import Foundation

/// API keys and tokens, read from a `.env` file that is never committed.
///
/// Nothing in the app requires a key today — Spotify is driven over AppleScript
/// and every system reading is public API — so this exists for what gets added
/// next, and so that a key never has to be pasted into source to try something.
public enum Secrets {

    /// Search order. The first file that exists wins.
    ///
    /// A packaged `.app` cannot see the project directory, so the real home for
    /// secrets is Application Support. The working directory is checked too, so
    /// `swift run` picks up the repo's own `.env` during development.
    public static func searchPaths(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> [URL] {
        var paths: [URL] = []
        if let override = environment["PILL_ENV_FILE"], !override.isEmpty {
            paths.append(URL(fileURLWithPath: override))
        }
        if let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            paths.append(support.appendingPathComponent("Pill/.env"))
        }
        paths.append(workingDirectory.appendingPathComponent(".env"))
        return paths
    }

    public static func load() -> [String: String] {
        for url in searchPaths() {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            return parse(text)
        }
        return [:]
    }

    /// Parses the `.env` format: `KEY=value`, one per line.
    ///
    /// Blank lines and `#` comments are skipped, a leading `export` is tolerated
    /// so the same file can be sourced by a shell, and surrounding quotes are
    /// stripped. A value may itself contain `=`, so only the first one splits.
    /// Anything unparseable is skipped rather than guessed at — a malformed line
    /// silently becoming a key is worse than it being absent.
    public static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }

            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}
