import Foundation
import PillCore

/// Reads mail metadata from Microsoft Graph.
///
/// Only the fields the pill shows are requested via `$select`, and unread-only
/// via `$filter`, so the response stays small — this runs on a periodic check
/// and there is no reason to pull whole mailboxes.
struct GraphMailClient {

    private let auth: GraphAuth
    private static let root = "https://graph.microsoft.com/v1.0"

    init(auth: GraphAuth) { self.auth = auth }

    // MARK: Wire format

    private struct Address: Decodable { let name: String?; let address: String? }
    private struct Recipient: Decodable { let emailAddress: Address? }
    private struct Message: Decodable {
        let id: String
        let subject: String?
        let receivedDateTime: Date?
        let isRead: Bool?
        let from: Recipient?
        let toRecipients: [Recipient]?
        let ccRecipients: [Recipient]?
    }
    private struct MessagePage: Decodable { let value: [Message] }
    private struct Me: Decodable { let mail: String?; let userPrincipalName: String? }

    // MARK: Requests

    /// The signed-in user's own address, needed for the direct-to-me rule.
    func myAddress() async throws -> String? {
        let me: Me = try await get("/me?$select=mail,userPrincipalName")
        return me.mail ?? me.userPrincipalName
    }

    func unreadInbox(limit: Int = 25) async throws -> [EmailMessage] {
        let path = "/me/mailFolders/inbox/messages"
            + "?$select=id,subject,from,toRecipients,ccRecipients,receivedDateTime,isRead"
            + "&$filter=isRead%20eq%20false"
            + "&$orderby=receivedDateTime%20desc"
            + "&$top=\(limit)"
        let page: MessagePage = try await get(path)
        return page.value.map { message in
            EmailMessage(
                id: message.id,
                subject: message.subject ?? "(no subject)",
                senderName: message.from?.emailAddress?.name ?? "",
                senderAddress: message.from?.emailAddress?.address ?? "",
                receivedAt: message.receivedDateTime ?? Date(),
                isRead: message.isRead ?? false,
                toRecipients: (message.toRecipients ?? []).compactMap { $0.emailAddress?.address },
                ccRecipients: (message.ccRecipients ?? []).compactMap { $0.emailAddress?.address }
            )
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: URL(string: Self.root + path)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw GraphAuth.AuthError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
