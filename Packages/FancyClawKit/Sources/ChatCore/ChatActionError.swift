import Foundation

public enum ChatActionError: LocalizedError {
    case busy, emptyMessage, unavailable, aborted
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .busy: "This chat already has a reply in progress."
        case .emptyMessage: "Enter a message to send."
        case .unavailable: "The chat is unavailable. Reconnect in FancyClaw."
        case .aborted: "The reply was stopped."
        case .failed(let message): message
        }
    }
}
