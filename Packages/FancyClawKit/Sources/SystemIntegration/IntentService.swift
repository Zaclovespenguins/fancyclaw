import Foundation

/// Registered by the app at launch; intents never construct a second socket or access credentials in an extension.
@MainActor public final class IntentService {
    public let ask: (String) async throws -> String
    public let newChat: () async throws -> Void
    public let openSession: (SessionEntity) async throws -> Void
    public let sessions: () throws -> [SessionEntity]

    public init(ask: @escaping (String) async throws -> String,
                newChat: @escaping () async throws -> Void,
                openSession: @escaping (SessionEntity) async throws -> Void,
                sessions: @escaping () throws -> [SessionEntity]) {
        self.ask = ask
        self.newChat = newChat
        self.openSession = openSession
        self.sessions = sessions
    }
}

public enum IntentError: LocalizedError {
    case notConnected, sessionUnavailable, emptyMessage, busy
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Open FancyClaw and connect to your Gateway first."
        case .sessionUnavailable: "This chat is no longer available on your configured Gateway."
        case .emptyMessage: "Enter a message to send to FancyClaw."
        case .busy: "The default chat already has a reply in progress. Try again when it finishes."
        case .failed(let message): message
        }
    }
}
