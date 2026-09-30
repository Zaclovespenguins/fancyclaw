import Foundation

/// The error object of a failed response: `{code, message, details?, retryable?, retryAfterMs?}`.
public struct GatewayErrorShape: Codable, Hashable, Sendable, Error {
    public var code: GatewayErrorCode
    public var message: String
    public var details: JSONValue?
    public var retryable: Bool?
    public var retryAfterMs: Int?

    public init(
        code: GatewayErrorCode, message: String, details: JSONValue? = nil,
        retryable: Bool? = nil, retryAfterMs: Int? = nil
    ) {
        self.code = code
        self.message = message
        self.details = details
        self.retryable = retryable
        self.retryAfterMs = retryAfterMs
    }

    /// The structured reason in `details.code`, which clients should branch on before `code`.
    public var detailCode: GatewayErrorDetailCode? {
        details?["code"]?.stringValue.map(GatewayErrorDetailCode.init(rawValue:))
    }

    /// The `details.reason` string, for example `"startup-sidecars"` on a startup `UNAVAILABLE`.
    public var detailReason: String? {
        details?["reason"]?.stringValue
    }

    /// The scope a `FORBIDDEN` + `MISSING_SCOPE` error says the caller lacks.
    public var missingScope: OperatorScope? {
        guard detailCode == .missingScope else { return nil }
        return details?["missingScope"]?.stringValue.map(OperatorScope.init(rawValue:))
    }

    /// The Gateway's advice for recovering from a connect failure.
    public var recommendedNextStep: ConnectRecoveryStep? {
        details?["recommendedNextStep"]?.stringValue.map(ConnectRecoveryStep.init(rawValue:))
    }

    /// Whether an `AUTH_TOKEN_MISMATCH` may be retried once with the stored device token.
    public var canRetryWithDeviceToken: Bool {
        details?["canRetryWithDeviceToken"]?.boolValue ?? false
    }

    /// The pending pairing request id carried by `PAIRING_REQUIRED`, for `openclaw devices approve`.
    public var pairingRequestId: String? {
        guard detailCode == .pairingRequired else { return nil }
        return details?["requestId"]?.stringValue
    }

    /// Whether this is the retryable `UNAVAILABLE` a Gateway returns while startup sidecars finish.
    public var isStartupUnavailable: Bool {
        code == .unavailable && detailReason == "startup-sidecars"
    }
}

/// Top-level response error codes (`ErrorCodes` in `gateway-error-details.ts`).
public enum GatewayErrorCode: OpenEnum {
    case notLinked
    case notPaired
    case agentTimeout
    case invalidRequest
    case forbidden
    case approvalNotFound
    case unavailable
    case unknown(String)

    public static let knownCases: [GatewayErrorCode] = [
        .notLinked, .notPaired, .agentTimeout, .invalidRequest, .forbidden, .approvalNotFound, .unavailable,
    ]

    public var rawValue: String {
        switch self {
        case .notLinked: "NOT_LINKED"
        case .notPaired: "NOT_PAIRED"
        case .agentTimeout: "AGENT_TIMEOUT"
        case .invalidRequest: "INVALID_REQUEST"
        case .forbidden: "FORBIDDEN"
        case .approvalNotFound: "APPROVAL_NOT_FOUND"
        case .unavailable: "UNAVAILABLE"
        case .unknown(let value): value
        }
    }
}

/// Structured error reasons carried in `error.details.code`.
///
/// Covers the connect-error codes FancyClaw reacts to (`connect-error-details.ts`) and the method-level
/// `MISSING_SCOPE` detail; everything else decodes as `.unknown`.
public enum GatewayErrorDetailCode: OpenEnum {
    case authRequired
    case authUnauthorized
    case authTokenMissing
    case authTokenMismatch
    case authPasswordMissing
    case authPasswordMismatch
    case authBootstrapTokenInvalid
    case authDeviceTokenMismatch
    case authScopeMismatch
    case authRateLimited
    case protocolMismatch
    case deviceIdentityRequired
    case deviceAuthInvalid
    case deviceAuthDeviceIdMismatch
    case deviceAuthSignatureExpired
    case deviceAuthNonceRequired
    case deviceAuthNonceMismatch
    case deviceAuthSignatureInvalid
    case deviceAuthPublicKeyInvalid
    case pairingRequired
    case clientVersionMismatch
    case missingScope
    case unknown(String)

    public static let knownCases: [GatewayErrorDetailCode] = [
        .authRequired, .authUnauthorized, .authTokenMissing, .authTokenMismatch, .authPasswordMissing,
        .authPasswordMismatch, .authBootstrapTokenInvalid, .authDeviceTokenMismatch, .authScopeMismatch,
        .authRateLimited, .protocolMismatch, .deviceIdentityRequired, .deviceAuthInvalid,
        .deviceAuthDeviceIdMismatch, .deviceAuthSignatureExpired, .deviceAuthNonceRequired,
        .deviceAuthNonceMismatch, .deviceAuthSignatureInvalid, .deviceAuthPublicKeyInvalid, .pairingRequired,
        .clientVersionMismatch, .missingScope,
    ]

    public var rawValue: String {
        switch self {
        case .authRequired: "AUTH_REQUIRED"
        case .authUnauthorized: "AUTH_UNAUTHORIZED"
        case .authTokenMissing: "AUTH_TOKEN_MISSING"
        case .authTokenMismatch: "AUTH_TOKEN_MISMATCH"
        case .authPasswordMissing: "AUTH_PASSWORD_MISSING"
        case .authPasswordMismatch: "AUTH_PASSWORD_MISMATCH"
        case .authBootstrapTokenInvalid: "AUTH_BOOTSTRAP_TOKEN_INVALID"
        case .authDeviceTokenMismatch: "AUTH_DEVICE_TOKEN_MISMATCH"
        case .authScopeMismatch: "AUTH_SCOPE_MISMATCH"
        case .authRateLimited: "AUTH_RATE_LIMITED"
        case .protocolMismatch: "PROTOCOL_MISMATCH"
        case .deviceIdentityRequired: "DEVICE_IDENTITY_REQUIRED"
        case .deviceAuthInvalid: "DEVICE_AUTH_INVALID"
        case .deviceAuthDeviceIdMismatch: "DEVICE_AUTH_DEVICE_ID_MISMATCH"
        case .deviceAuthSignatureExpired: "DEVICE_AUTH_SIGNATURE_EXPIRED"
        case .deviceAuthNonceRequired: "DEVICE_AUTH_NONCE_REQUIRED"
        case .deviceAuthNonceMismatch: "DEVICE_AUTH_NONCE_MISMATCH"
        case .deviceAuthSignatureInvalid: "DEVICE_AUTH_SIGNATURE_INVALID"
        case .deviceAuthPublicKeyInvalid: "DEVICE_AUTH_PUBLIC_KEY_INVALID"
        case .pairingRequired: "PAIRING_REQUIRED"
        case .clientVersionMismatch: "CLIENT_VERSION_MISMATCH"
        case .missingScope: "MISSING_SCOPE"
        case .unknown(let value): value
        }
    }
}

/// The `details.recommendedNextStep` hint on connect failures.
public enum ConnectRecoveryStep: OpenEnum {
    case retryWithDeviceToken
    case updateAuthConfiguration
    case updateAuthCredentials
    case waitThenRetry
    case reviewAuthConfiguration
    case unknown(String)

    public static let knownCases: [ConnectRecoveryStep] = [
        .retryWithDeviceToken, .updateAuthConfiguration, .updateAuthCredentials, .waitThenRetry,
        .reviewAuthConfiguration,
    ]

    public var rawValue: String {
        switch self {
        case .retryWithDeviceToken: "retry_with_device_token"
        case .updateAuthConfiguration: "update_auth_configuration"
        case .updateAuthCredentials: "update_auth_credentials"
        case .waitThenRetry: "wait_then_retry"
        case .reviewAuthConfiguration: "review_auth_configuration"
        case .unknown(let value): value
        }
    }
}

extension GatewayErrorShape: LocalizedError {
    public var errorDescription: String? { message }
}
