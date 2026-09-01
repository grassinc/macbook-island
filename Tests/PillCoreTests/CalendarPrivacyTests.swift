import Foundation
@testable import PillCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private func at(_ o: TimeInterval) -> Date { t0.addingTimeInterval(o) }

func runCalendarPrivacyTests(_ r: TestRunner) {

    // MARK: One-click join

    r.test("Zoom, Meet and Teams links are recognised") { r in
        r.expectEqual(VideoCallLink.find(in: ["https://zoom.us/j/91234567890"])?.host, "zoom.us", "zoom")
        r.expectEqual(VideoCallLink.find(in: ["https://meet.google.com/abc-defg-hij"])?.host, "meet.google.com", "meet")
        r.expectEqual(VideoCallLink.find(in: ["https://teams.microsoft.com/l/meetup-join/19%3ameeting"])?.host,
                      "teams.microsoft.com", "teams")
    }

    r.test("a link buried in notes is still found") { r in
        let notes = "Agenda attached.\nJoin: https://meet.google.com/xyz-abcd-efg\nDial-in optional."
        r.expectEqual(VideoCallLink.find(in: [nil, notes])?.absoluteString,
                      "https://meet.google.com/xyz-abcd-efg", "extracted from surrounding prose")
    }

    r.test("fields are searched in order, so the location wins over notes") { r in
        let found = VideoCallLink.find(in: ["https://zoom.us/j/111", "https://meet.google.com/aaa-bbbb-ccc"])
        r.expectEqual(found?.host, "zoom.us", "first field wins")
    }

    // An ordinary web link in an event must not be offered as "Join".
    r.test("a non-meeting URL is not treated as a call link") { r in
        r.expect(VideoCallLink.find(in: ["https://example.com/agenda.pdf"]) == nil, "random links ignored")
        r.expect(VideoCallLink.find(in: ["Conference Room B"]) == nil, "a room name is not a link")
        r.expect(VideoCallLink.find(in: [nil, nil]) == nil, "nothing to find")
    }

    // MARK: Next-event selection

    r.test("the next event is the soonest one still ahead") { r in
        let events = [
            // Genuinely finished: started two hours ago, default 30m duration.
            CalendarEvent(title: "Past", startsAt: at(-7200), isAllDay: false),
            CalendarEvent(title: "Soon", startsAt: at(900), isAllDay: false),
            CalendarEvent(title: "Later", startsAt: at(7200), isAllDay: false),
        ]
        r.expectEqual(CalendarPeek.next(from: events, at: t0)?.title, "Soon", "soonest upcoming wins")
    }

    // An all-day event has no meaningful countdown and would pin itself to the
    // pill all day, crowding out everything else.
    r.test("all-day events are not offered as the next event") { r in
        let events = [CalendarEvent(title: "Public holiday", startsAt: at(60), isAllDay: true)]
        r.expect(CalendarPeek.next(from: events, at: t0) == nil, "all-day events are skipped")
    }

    r.test("an event already under way still counts as current") { r in
        let events = [CalendarEvent(title: "Standup", startsAt: at(-120), isAllDay: false, durationMinutes: 30)]
        r.expectEqual(CalendarPeek.next(from: events, at: t0)?.title, "Standup", "in-progress meeting still shows")
    }

    r.test("countdown reads in minutes, then hours") { r in
        r.expectEqual(CalendarPeek.countdown(to: at(90), from: t0), "in 1m", "under an hour")
        r.expectEqual(CalendarPeek.countdown(to: at(3600), from: t0), "in 1h", "an hour out")
        r.expectEqual(CalendarPeek.countdown(to: at(5400), from: t0), "in 1h 30m", "mixed")
        r.expectEqual(CalendarPeek.countdown(to: at(-60), from: t0), "now", "already started")
    }

    // MARK: Screen-share redaction

    r.test("screen-share mode hides calendar titles but keeps the shape") { r in
        let event = Activity(id: "calendar", kind: .calendar, title: "Salary review with Dana",
                             subtitle: "in 10m", priority: .info, startedAt: t0)
        let safe = PrivacyMode.screenShare.redact(event)
        r.expect(safe.title.contains("Dana") == false, "the title is gone")
        r.expectEqual(safe.title, "Event", "replaced with a neutral label")
        r.expectEqual(safe.subtitle, "in 10m", "timing is not sensitive, so it stays useful")
    }

    r.test("screen-share mode hides screenshot filenames") { r in
        let shot = Activity(id: "shelf", kind: .screenshot, title: "offer-letter-signed.png",
                            priority: .transient, startedAt: t0)
        r.expectEqual(PrivacyMode.screenShare.redact(shot).title, "Screenshot", "filename suppressed")
    }

    // Volume is not private, and blanking it would make the HUD useless in a
    // call, which is exactly when people adjust their volume.
    r.test("screen-share mode leaves non-sensitive activities alone") { r in
        let hud = Activity(id: "hud", kind: .hud, title: "Volume",
                           priority: .interruptive, startedAt: t0, progress: 0.4)
        let safe = PrivacyMode.screenShare.redact(hud)
        r.expectEqual(safe.title, "Volume", "untouched")
        r.expectEqual(safe.progress, 0.4, "meter still works")
    }

    r.test("normal mode changes nothing") { r in
        let event = Activity(id: "calendar", kind: .calendar, title: "Salary review",
                             priority: .info, startedAt: t0)
        r.expectEqual(PrivacyMode.normal.redact(event).title, "Salary review", "no redaction when not sharing")
    }
}
