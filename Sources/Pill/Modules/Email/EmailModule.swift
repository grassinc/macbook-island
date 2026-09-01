import AppKit
import Foundation
import PillCore

enum EmailState: Equatable {
    case notConfigured
    case signedOut
    case awaitingCode(userCode: String, url: URL)
    case signedIn
    case failed(String)
}

@MainActor
final class EmailStore: ObservableObject {
    @Published fileprivate(set) var state: EmailState = .notConfigured
    @Published fileprivate(set) var important: [EmailMessage] = []
    @Published fileprivate(set) var silentUnread = 0
    @Published fileprivate(set) var lastChecked: Date?
}

/// Outlook mail via Microsoft Graph.
///
/// Graph is used rather than AppleScript because the new Outlook (Hx engine)
/// does not expose real accounts to the legacy scripting object model — verified
/// on this machine: `get every account` fails with -1728 and only local
/// "On My Computer" folders are visible, with an empty Inbox.
///
/// This is the second deliberate exception to the no-polling rule. Graph's push
/// mechanism is webhooks, which require a public HTTPS endpoint a desktop app
/// does not have. The interval is therefore long and the query narrow, and it
/// only runs while signed in — the brief's own design asks for batched digests
/// rather than per-message interruptions, so a periodic check matches the
/// intended behaviour rather than fighting it.
@MainActor
final class EmailModule: PillModule {
    static let identifier = "email"

    private let store: EmailStore
    private var context: ModuleContext?
    private var auth: GraphAuth?
    private var client: GraphMailClient?
    private var filter = EmailFilter(myAddresses: [])
    private var pollTask: Task<Void, Never>?
    private var lastSeenIDs: Set<String> = []
    private var batchStartedAt = Date()

    /// Long on purpose. Mail is not a real-time signal and the brief explicitly
    /// wants digests, not interruptions.
    private let interval: TimeInterval = 120

    init(store: EmailStore) { self.store = store }

    func activate(context: ModuleContext) {
        self.context = context

        guard let configuration = EmailConfiguration.load() else {
            store.state = .notConfigured
            Log.permissions.notice("graph: no client id configured")
            return
        }
        let auth = GraphAuth(configuration: configuration)
        self.auth = auth
        self.client = GraphMailClient(auth: auth)

        Task { [weak self] in
            guard let self else { return }
            if await auth.isSignedIn {
                self.store.state = .signedIn
                await self.resolveIdentity()
                self.startPolling()
            } else {
                self.store.state = .signedOut
            }
        }
    }

    func deactivate() {
        pollTask?.cancel()
        pollTask = nil
        context?.retract(id: Self.identifier)
    }

    // MARK: - Sign in

    func signIn() {
        guard let auth else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let code = try await auth.beginDeviceCodeFlow()
                self.store.state = .awaitingCode(userCode: code.userCode, url: code.verificationURL)
                // Open the page and put the code on the clipboard: retyping a
                // one-time code from a 30pt strip is needless friction.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
                NSWorkspace.shared.open(code.verificationURL)

                try await auth.pollForToken(code)
                self.store.state = .signedIn
                await self.resolveIdentity()
                self.startPolling()
                Log.permissions.notice("graph: signed in")
            } catch {
                self.store.state = .failed(error.localizedDescription)
                Log.permissions.error("graph sign-in: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func signOut() {
        pollTask?.cancel()
        pollTask = nil
        Task { [weak self] in
            await self?.auth?.signOut()
            self?.store.state = .signedOut
            self?.store.important = []
            self?.store.silentUnread = 0
            self?.context?.retract(id: Self.identifier)
        }
    }

    /// The direct-to-me rule needs to know who "me" is.
    private func resolveIdentity() async {
        guard let client else { return }
        if let address = (try? await client.myAddress()) ?? nil {
            filter = EmailFilter(myAddresses: [address], vipAddresses: [])
            Log.permissions.notice("graph: identity resolved")
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(nanoseconds: UInt64((self?.interval ?? 120) * 1_000_000_000))
            }
        }
    }

    private func check() async {
        guard let client else { return }
        do {
            let messages = try await client.unreadInbox()
            store.lastChecked = Date()

            let split = filter.partition(messages)
            store.important = split.important
            store.silentUnread = split.silentUnreadCount

            // Only genuinely new arrivals since the last look are announced,
            // otherwise the same unread mail would re-interrupt every cycle.
            let fresh = split.important.filter { !lastSeenIDs.contains($0.id) }
            lastSeenIDs = Set(messages.map(\.id))

            guard let digest = EmailDigest.summary(of: fresh, since: batchStartedAt) else { return }
            batchStartedAt = Date()

            let now = Date()
            context?.publish(Activity(
                id: Self.identifier,
                kind: .email,
                title: fresh.count == 1 ? fresh[0].displaySender : digest.text,
                subtitle: fresh.count == 1 ? fresh[0].subject : nil,
                priority: .info,
                startedAt: now,
                expiresAt: now.addingTimeInterval(12)
            ))
            Log.activity.notice("email: \(fresh.count, privacy: .public) new, \(split.silentUnreadCount, privacy: .public) silent")
        } catch {
            Log.activity.error("graph check failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Where the Azure client ID lives. Kept out of the repo: it is per-user setup,
/// not source.
enum EmailConfiguration {
    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Pill/graph.json")
    }

    static func load() -> GraphAuth.Configuration? {
        guard let data = try? Data(contentsOf: fileURL),
              let configuration = try? JSONDecoder().decode(GraphAuth.Configuration.self, from: data),
              !configuration.clientID.isEmpty else { return nil }
        return configuration
    }
}
