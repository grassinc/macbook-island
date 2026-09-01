import Foundation
@testable import PillCore

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private func at(_ o: TimeInterval) -> Date { t0.addingTimeInterval(o) }

private func msg(_ id: String, from: String, to: [String] = ["me@ada.edu.az"],
                 cc: [String] = [], subject: String = "Subject",
                 read: Bool = false, at when: Date = t0) -> EmailMessage {
    EmailMessage(id: id, subject: subject, senderName: from, senderAddress: from,
                 receivedAt: when, isRead: read, toRecipients: to, ccRecipients: cc)
}

func runEmailTests(_ r: TestRunner) {
    let filter = EmailFilter(myAddresses: ["me@ada.edu.az"],
                             vipAddresses: ["dean@ada.edu.az"])

    // The brief's core rule: a pill that animates 60 times a day gets ignored
    // and poisons everything else sharing that space.
    r.test("mail addressed directly to me is important") { r in
        r.expect(filter.isImportant(msg("1", from: "colleague@x.com", to: ["me@ada.edu.az"])),
                 "direct-to-me counts")
    }

    r.test("mail where I am only in CC is not important") { r in
        let m = msg("2", from: "someone@x.com", to: ["other@x.com"], cc: ["me@ada.edu.az"])
        r.expect(filter.isImportant(m) == false, "CC is not direct")
    }

    r.test("a VIP is important even when I am only in CC") { r in
        let m = msg("3", from: "dean@ada.edu.az", to: ["all@ada.edu.az"], cc: ["me@ada.edu.az"])
        r.expect(filter.isImportant(m), "VIP overrides the direct-to-me rule")
    }

    r.test("bulk mail addressed to a list is not important") { r in
        let m = msg("4", from: "newsletter@x.com", to: ["students@ada.edu.az"])
        r.expect(filter.isImportant(m) == false, "list mail stays silent")
    }

    r.test("address matching ignores case and whitespace") { r in
        let m = msg("5", from: "x@y.com", to: ["  ME@ADA.edu.az "])
        r.expect(filter.isImportant(m), "addresses normalise before comparison")
    }

    r.test("already-read mail is never important") { r in
        let m = msg("6", from: "dean@ada.edu.az", to: ["me@ada.edu.az"], read: true)
        r.expect(filter.isImportant(m) == false, "read mail cannot interrupt")
    }

    // Everything filtered out still has to be counted, silently.
    r.test("unimportant unread mail feeds a silent count") { r in
        let messages = [
            msg("a", from: "dean@ada.edu.az"),                                   // important
            msg("b", from: "list@x.com", to: ["students@ada.edu.az"]),           // not
            msg("c", from: "list2@x.com", to: ["students@ada.edu.az"]),          // not
            msg("d", from: "x@y.com", to: ["me@ada.edu.az"], read: true),        // read
        ]
        let split = filter.partition(messages)
        r.expectEqual(split.important.count, 1, "one deserves an interruption")
        r.expectEqual(split.silentUnreadCount, 2, "two counted silently, read mail excluded")
    }

    // Batching, so the pill reports once rather than sixty times.
    r.test("a digest counts what arrived and when it started") { r in
        let messages = [msg("a", from: "x@y.com", at: at(60)), msg("b", from: "z@y.com", at: at(120))]
        let digest = EmailDigest.summary(of: messages, since: t0)
        r.expectEqual(digest?.count, 2, "counts the batch")
        r.expect(digest?.text.hasPrefix("2 new") == true, "reads as a count first")
    }

    r.test("one message reads in the singular") { r in
        let digest = EmailDigest.summary(of: [msg("a", from: "x@y.com")], since: t0)
        r.expect(digest?.text.hasPrefix("1 new message") == true, "no '1 new messages'")
    }

    r.test("an empty batch produces no digest at all") { r in
        r.expect(EmailDigest.summary(of: [], since: t0) == nil, "nothing to say means say nothing")
    }
}
