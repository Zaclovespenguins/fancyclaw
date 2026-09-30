import Foundation

public enum AttachmentError: LocalizedError, Equatable, Sendable {
    case emptyFile
    case invalidImage
    case tooLarge(fileName: String, limit: Int)
    case frameTooLarge

    public var errorDescription: String? {
        switch self {
        case .emptyFile: "This file is empty. Choose another file."
        case .invalidImage: "This image couldn’t be read. Choose another image."
        case .tooLarge(let name, let limit):
            "\(name) must be smaller than \(ByteCountFormatter.string(fromByteCount: Int64(max(0, limit)), countStyle: .file))."
        case .frameTooLarge: "This message exceeds the Gateway’s upload limit. Remove an attachment or shorten the message."
        }
    }
}
