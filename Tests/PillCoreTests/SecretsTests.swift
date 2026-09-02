import Foundation
import PillCore

func runSecretsTests(_ runner: TestRunner) {
    runner.test("Secrets.parse") { t in
        let parsed = Secrets.parse("""
        # a comment
        LASTFM_API_KEY=abc123

          SPACED  =  value with spaces
        export EXPORTED=fromshell
        QUOTED="quoted value"
        SINGLE='single quoted'
        URL=https://example.com/a?b=c&d=e
        EMPTY=
        """)
        t.expectEqual(parsed["LASTFM_API_KEY"], "abc123", "plain key")
        t.expectEqual(parsed["SPACED"], "value with spaces", "whitespace is trimmed around both sides")
        t.expectEqual(parsed["EXPORTED"], "fromshell", "a leading export is tolerated")
        t.expectEqual(parsed["QUOTED"], "quoted value", "double quotes stripped")
        t.expectEqual(parsed["SINGLE"], "single quoted", "single quotes stripped")
        // Only the first = splits, or any URL with a query string would be cut short.
        t.expectEqual(parsed["URL"], "https://example.com/a?b=c&d=e", "value may contain =")
        t.expectEqual(parsed["EMPTY"], "", "an empty value is a value, not a missing key")
        t.expectEqual(parsed["# a comment"], nil, "comments are not keys")
        t.expectEqual(parsed.count, 7, "nothing else was invented")
    }

    runner.test("Secrets.parse rejects junk") { t in
        let parsed = Secrets.parse("no equals sign here\n=novalue\n\n   \n")
        t.expectEqual(parsed.count, 0, "unparseable lines are skipped, never guessed at")
    }

    runner.test("Secrets.searchPaths") { t in
        let paths = Secrets.searchPaths(environment: ["PILL_ENV_FILE": "/tmp/custom.env"],
                                        workingDirectory: URL(fileURLWithPath: "/work"))
        t.expectEqual(paths.first?.path, "/tmp/custom.env", "an explicit override wins")
        t.expectEqual(paths.last?.path, "/work/.env", "the working directory is the last resort")
        t.expect(paths.contains { $0.path.hasSuffix("Pill/.env") },
                 "Application Support is searched, since a bundled app cannot see the project")

        let none = Secrets.searchPaths(environment: [:], workingDirectory: URL(fileURLWithPath: "/work"))
        t.expect(!none.contains { $0.path == "/tmp/custom.env" }, "no override, no extra path")
    }
}
