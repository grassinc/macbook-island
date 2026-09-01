import OSLog

/// Unified-logging channels.
///
/// An agent app has no console to print to, so diagnostics go through os_log
/// where they can be read with:
///   log stream --predicate 'subsystem == "com.pill.app"'
enum Log {
    static let hud = Logger(subsystem: "com.pill.app", category: "hud")
    static let audio = Logger(subsystem: "com.pill.app", category: "audio")
    static let activity = Logger(subsystem: "com.pill.app", category: "activity")
    static let permissions = Logger(subsystem: "com.pill.app", category: "permissions")
}
