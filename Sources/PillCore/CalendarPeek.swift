import Foundation

/// A calendar entry, modelled without EventKit so the selection and formatting
/// rules can be tested headlessly.
public struct CalendarEvent: Equatable, Sendable {
    public let title: String
    public let startsAt: Date
    public let isAllDay: Bool
    public let durationMinutes: Int
    public let location: String?
    public let notes: String?
    public let urlString: String?

    public init(title: String,
                startsAt: Date,
                isAllDay: Bool,
                durationMinutes: Int = 30,
                location: String? = nil,
                notes: String? = nil,
                urlString: String? = nil) {
        self.title = title
        self.startsAt = startsAt
        self.isAllDay = isAllDay
        self.durationMinutes = durationMinutes
        self.location = location
        self.notes = notes
        self.urlString = urlString
    }

    public var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60)) }

    /// The one-click join link, if this event has one.
    public var videoCallURL: URL? {
        VideoCallLink.find(in: [location, urlString, notes])
    }
}

/// Finds a joinable meeting link.
///
/// Restricted to known conferencing hosts on purpose. Offering a "Join" button
/// that opens an agenda PDF would be worse than offering nothing.
public enum VideoCallLink {

    private static let hosts: Set<String> = [
        "zoom.us", "us02web.zoom.us", "us04web.zoom.us",
        "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "whereby.com", "meet.jit.si", "webex.com", "discord.gg",
    ]

    /// Fields are searched in the order given, so a caller can express priority.
    public static func find(in fields: [String?]) -> URL? {
        for field in fields {
            guard let field, !field.isEmpty else { continue }
            if let match = firstMeetingURL(in: field) { return match }
        }
        return nil
    }

    private static func firstMeetingURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            guard let url = match.url, let host = url.host?.lowercased() else { continue }
            if hosts.contains(host) || hosts.contains(where: { host.hasSuffix(".\($0)") }) {
                return url
            }
        }
        return nil
    }
}

public enum CalendarPeek {

    /// The event worth showing: the soonest one that has not finished yet.
    ///
    /// All-day events are excluded — they have no meaningful countdown and would
    /// occupy the pill for a whole day, crowding out everything else.
    public static func next(from events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        events
            .filter { !$0.isAllDay && $0.endsAt > now }
            .min { $0.startsAt < $1.startsAt }
    }

    /// Short, glanceable countdown.
    public static func countdown(to date: Date, from now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "now" }

        let minutes = seconds / 60
        if minutes < 60 { return "in \(max(minutes, 1))m" }

        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "in \(hours)h" : "in \(hours)h \(remainder)m"
    }
}
