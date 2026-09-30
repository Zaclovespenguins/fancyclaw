import CryptoKit
import Foundation
import Security

/// URLSession delegate that requires the presented leaf certificate to match a setup-code fingerprint.
public final class GatewayTLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let expectedFingerprint: String

    public init(fingerprint: String) {
        expectedFingerprint = Self.normalize(fingerprint)
        super.init()
    }

    public static func normalize(_ fingerprint: String) -> String {
        fingerprint.lowercased().filter { $0.isHexDigit }
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                           completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let certificate = certificates.first else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data)
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard actual == expectedFingerprint else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
