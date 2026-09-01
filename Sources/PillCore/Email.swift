import Foundation

/// One message, carrying only what the pill needs.
///
/// Deliberately no body: the Graph scope used is `Mail.ReadBasic`, which cannot
/// return message bodies at all. The brief asked to prefer metadata-only access
/// where sufficient, and for showing sender and subject it is.
public struct EmailMessage: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let subject: String
    public let senderName: String
    public let senderAddress: String
    public let receivedAt: Date
    public let isRead: Bool
    public let toRecipients: [String]
    public let ccRecipients: [String]

    public init(id: String, subject: String, senderName: String, senderAddress: String,
                receivedAt: Date, isRead: Bool,
                toRecipients: [String] = [], ccRecipients: [String] = []) {
        self.id = id
        self.subject = subject
        self.senderName = senderName
        self.senderAddress = senderAddress
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.toRecipients = toRecipients
        self.ccRecipients = ccRecipients
    }

    /// Falls back to the address when a display name is missing.
    public var displaySender: String {
        senderName.isEmpty ? senderAddress : senderName
    }
}

/// Decides what is worth interrupting for.
///
/// The brief's reasoning, which drives this whole design: a pill that animates
/// sixty times a day gets ignored, and poisons every other activity sharing that
/// space. So the default is hard filtering — direct-to-me or a VIP — and
/// everything else feeds a silent count.
public struct EmailFilter: Sendable {
    public let myAddresses: Set<String>
    public let vipAddresses: Set<String>

    public init(myAddresses: Set<String>, vipAddresses: Set<String> = []) {
        self.myAddresses = Set(myAddresses.map(Self.normalise))
        self.vipAddresses = Set(vipAddresses.map(Self.normalise))
    }

    private static func normalise(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public func isImportant(_ message: EmailMessage) -> Bool {
        guard !message.isRead else { return false }
        if vipAddresses.contains(Self.normalise(message.senderAddress)) { return true }
        // Directly addressed, not merely copied. Being in CC on a list is the
        // single largest source of noise.
        return message.toRecipients
            .map(Self.normalise)
            .contains { myAddresses.contains($0) }
    }

    public struct Partition: Sendable {
        public let important: [EmailMessage]
        public let silentUnreadCount: Int
    }

    public func partition(_ messages: [EmailMessage]) -> Partition {
        let unread = messages.filter { !$0.isRead }
        let important = unread.filter(isImportant)
        return Partition(important: important,
                         silentUnreadCount: unread.count - important.count)
    }
}

/// Batches arrivals into one report instead of interrupting per message.
public enum EmailDigest {
    public struct Summary: Equatable, Sendable {
        public let count: Int
        public let text: String
        public let since: Date
    }

    public static func summary(of messages: [EmailMessage], since: Date) -> Summary? {
        guard !messages.isEmpty else { return nil }
        let noun = messages.count == 1 ? "message" : "messages"

        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let clock = formatter.string(from: since).lowercased()

        return Summary(count: messages.count,
                       text: "\(messages.count) new \(noun) since \(clock)",
                       since: since)
    }
}
