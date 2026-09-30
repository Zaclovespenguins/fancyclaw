import Foundation
import GatewayProtocol
import ImageIO
import UniformTypeIdentifiers

/// Serial image preparation and file reads happen off the main actor.
public actor AttachmentPipeline {
    // A local import ceiling bounds memory before compressed image preparation.
    public static let maxImportBytes = 100 * 1024 * 1024
    public init() {}

    public func prepareFile(at url: URL, limits: HelloOK.AttachmentLimits?) throws -> PreparedAttachment {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let mime = Self.mimeType(for: url.lastPathComponent)
        let ceiling = mime.hasPrefix("image/") ? Self.maxImportBytes : min(Self.maxImportBytes, Self.fileLimit(limits))
        var data = Data()
        while let chunk = try file.read(upToCount: min(1024 * 1024, max(1, ceiling - data.count + 1))), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
            guard data.count <= ceiling else { throw AttachmentError.tooLarge(fileName: url.lastPathComponent, limit: ceiling) }
        }
        return try prepare(data: data, fileName: url.lastPathComponent, limits: limits)
    }

    public func prepare(data: Data, fileName: String, imageRequired: Bool = false,
                        limits: HelloOK.AttachmentLimits?) throws -> PreparedAttachment {
        guard !data.isEmpty else { throw AttachmentError.emptyFile }
        guard data.count <= Self.maxImportBytes else {
            throw AttachmentError.tooLarge(fileName: fileName, limit: Self.maxImportBytes)
        }
        let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        let mime = Self.mimeType(for: fileName)
        if let source, let identifier = CGImageSourceGetType(source),
           UTType(identifier as String)?.conforms(to: .image) == true {
            return try prepareImage(source, fileName: fileName, limit: Self.imageLimit(limits))
        }
        guard !imageRequired && !mime.hasPrefix("image/") else { throw AttachmentError.invalidImage }
        guard data.count <= Self.fileLimit(limits) else {
            throw AttachmentError.tooLarge(fileName: fileName, limit: Self.fileLimit(limits))
        }
        return PreparedAttachment(data: data, fileName: fileName, mimeType: mime)
    }

    public nonisolated static func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
    }

    // Conservative fallbacks for older Gateways that omit attachment policy.
    private nonisolated static func fileLimit(_ limits: HelloOK.AttachmentLimits?) -> Int {
        max(0, limits?.maxBytes ?? 10 * 1024 * 1024)
    }
    private nonisolated static func imageLimit(_ limits: HelloOK.AttachmentLimits?) -> Int {
        min(fileLimit(limits), max(0, limits?.maxImageBytes ?? 5 * 1024 * 1024))
    }

    public func validateSubmission(_ attachments: [PreparedAttachment], params: ChatSendParams, policy: HelloOK.Policy?) throws {
        try Self.validate(attachments, params: params, policy: policy)
    }

    public nonisolated static func validate(_ attachments: [PreparedAttachment], params: ChatSendParams,
                                           policy: HelloOK.Policy?) throws {
        for attachment in attachments {
            let limit = attachment.mimeType.hasPrefix("image/") ? imageLimit(policy?.attachments) : fileLimit(policy?.attachments)
            guard attachment.data.count <= limit else {
                throw AttachmentError.tooLarge(fileName: attachment.fileName, limit: limit)
            }
        }
        let frame = RequestFrame(id: "00000000-0000-0000-0000-000000000000", method: "chat.send", params: params)
        let encoded = try GatewayCoding.encoder().encode(frame)
        guard encoded.count <= (policy?.maxPayload ?? 25 * 1024 * 1024) else { throw AttachmentError.frameTooLarge }
    }

    private func prepareImage(_ source: CGImageSource, fileName: String, limit: Int) throws -> PreparedAttachment {
        var dimension = 2048
        while dimension >= 64 {
            try Task.checkCancellation()
            guard let image = Self.thumbnail(source, dimension: dimension) else { throw AttachmentError.invalidImage }
            for quality in [0.85, 0.65, 0.45] {
                let bytes = try Self.jpeg(image, quality: quality)
                if bytes.count <= limit {
                    let name = (fileName as NSString).deletingPathExtension + ".jpg"
                    let preview = Self.thumbnail(source, dimension: 160).flatMap { try? Self.jpeg($0, quality: 0.65) }
                    return PreparedAttachment(data: bytes, thumbnail: preview, fileName: name, mimeType: "image/jpeg",
                                              width: image.width, height: image.height)
                }
            }
            dimension /= 2
        }
        throw AttachmentError.tooLarge(fileName: fileName, limit: limit)
    }

    private static func thumbnail(_ source: CGImageSource, dimension: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: dimension,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private static func jpeg(_ image: CGImage, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AttachmentError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AttachmentError.invalidImage }
        return output as Data
    }
}
