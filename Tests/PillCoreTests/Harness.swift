import Foundation

/// Minimal test harness. The Command Line Tools ship no XCTest and no
/// swift-testing, and requiring a full Xcode install just to get an assertion
/// function is a poor trade. This provides red/green and a non-zero exit code,
/// which is everything the workflow actually needs.
final class TestRunner {
    private var failures: [String] = []
    private var passed = 0
    private var current = "?"

    func test(_ name: String, _ body: (TestRunner) -> Void) {
        current = name
        body(self)
    }

    func expect(_ condition: Bool, _ what: String, line: UInt = #line) {
        if condition { passed += 1 }
        else { failures.append("[\(current)] \(what)  (line \(line))") }
    }

    func expectEqual<T: Equatable>(_ actual: T?, _ expected: T?, _ what: String, line: UInt = #line) {
        if actual == expected { passed += 1 }
        else {
            failures.append("[\(current)] \(what): expected \(describe(expected)), got \(describe(actual))  (line \(line))")
        }
    }

    private func describe<T>(_ value: T?) -> String {
        value.map { "\($0)" } ?? "nil"
    }

    func finish() -> Never {
        for failure in failures { print("  FAIL  \(failure)") }
        let total = passed + failures.count
        print(failures.isEmpty
              ? "\nall \(total) checks passed"
              : "\n\(passed)/\(total) checks passed, \(failures.count) FAILED")
        exit(failures.isEmpty ? 0 : 1)
    }
}
