import Foundation

struct HomeSendError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
