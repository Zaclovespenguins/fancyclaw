/// The `connect.challenge` event payload the Gateway sends as soon as the socket opens.
public struct ConnectChallenge: Codable, Hashable, Sendable {
    public var nonce: String
    /// Milliseconds since 1970; signed back as `device.signedAt`.
    public var ts: Int

    public init(nonce: String, ts: Int) {
        self.nonce = nonce
        self.ts = ts
    }
}

/// Parameters of the `connect` request, which must be the first frame a client sends.
///
/// The schema is closed: every property here is one the Gateway accepts, and `nil` values are omitted.
public struct ConnectParams: Codable, Hashable, Sendable {
    public var minProtocol: Int
    public var maxProtocol: Int
    public var client: ClientInfo
    public var role: GatewayRole?
    public var scopes: [OperatorScope]?
    public var caps: [ClientCapability]?
    public var auth: ConnectAuth?
    public var locale: String?
    public var userAgent: String?
    public var device: DeviceProof?

    public init(
        minProtocol: Int = ProtocolVersion.current, maxProtocol: Int = ProtocolVersion.current,
        client: ClientInfo, role: GatewayRole? = nil, scopes: [OperatorScope]? = nil,
        caps: [ClientCapability]? = nil, auth: ConnectAuth? = nil, locale: String? = nil,
        userAgent: String? = nil, device: DeviceProof? = nil
    ) {
        self.minProtocol = minProtocol
        self.maxProtocol = maxProtocol
        self.client = client
        self.role = role
        self.scopes = scopes
        self.caps = caps
        self.auth = auth
        self.locale = locale
        self.userAgent = userAgent
        self.device = device
    }
}

/// `connect.params.client`: who is connecting.
public struct ClientInfo: Codable, Hashable, Sendable {
    public var id: GatewayClientID
    public var displayName: String?
    public var version: String
    public var platform: String
    public var deviceFamily: String?
    public var modelIdentifier: String?
    public var timeZone: String?
    public var mode: GatewayClientMode
    public var instanceId: String?

    public init(
        id: GatewayClientID, displayName: String? = nil, version: String, platform: String,
        deviceFamily: String? = nil, modelIdentifier: String? = nil, timeZone: String? = nil,
        mode: GatewayClientMode, instanceId: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.platform = platform
        self.deviceFamily = deviceFamily
        self.modelIdentifier = modelIdentifier
        self.timeZone = timeZone
        self.mode = mode
        self.instanceId = instanceId
    }
}

/// `connect.params.auth`: the credential presented for this connection.
public struct ConnectAuth: Codable, Hashable, Sendable {
    public var token: String?
    public var bootstrapToken: String?
    public var deviceToken: String?
    public var password: String?

    public init(token: String? = nil, bootstrapToken: String? = nil, deviceToken: String? = nil, password: String? = nil) {
        self.token = token
        self.bootstrapToken = bootstrapToken
        self.deviceToken = deviceToken
        self.password = password
    }
}

/// `connect.params.device`: proof that the client holds the device's Ed25519 private key.
public struct DeviceProof: Codable, Hashable, Sendable {
    /// Lowercase hex SHA-256 of the raw 32-byte public key.
    public var id: String
    /// Base64url (unpadded) raw public key.
    public var publicKey: String
    /// Base64url (unpadded) signature over the v3 payload.
    public var signature: String
    /// The challenge `ts`, in milliseconds.
    public var signedAt: Int
    /// The challenge nonce.
    public var nonce: String

    public init(id: String, publicKey: String, signature: String, signedAt: Int, nonce: String) {
        self.id = id
        self.publicKey = publicKey
        self.signature = signature
        self.signedAt = signedAt
        self.nonce = nonce
    }
}

/// The successful `connect` response payload.
///
/// The Gateway sends a large, evolving snapshot; only the parts FancyClaw uses are modeled, and unknown
/// fields are ignored.
public struct HelloOK: Codable, Hashable, Sendable {
    public var `protocol`: Int
    public var server: Server
    public var features: Features
    public var snapshot: Snapshot
    public var auth: Auth
    public var policy: Policy

    public init(protocol: Int, server: Server, features: Features, snapshot: Snapshot, auth: Auth, policy: Policy) {
        self.protocol = `protocol`
        self.server = server
        self.features = features
        self.snapshot = snapshot
        self.auth = auth
        self.policy = policy
    }

    private enum CodingKeys: String, CodingKey {
        case type, `protocol`, server, features, snapshot, auth, policy
    }

    private static let type = "hello-ok"

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == Self.type else {
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "Expected hello-ok but found \(type).")
        }
        `protocol` = try container.decode(Int.self, forKey: .protocol)
        server = try container.decode(Server.self, forKey: .server)
        features = try container.decode(Features.self, forKey: .features)
        snapshot = try container.decode(Snapshot.self, forKey: .snapshot)
        auth = try container.decode(Auth.self, forKey: .auth)
        policy = try container.decode(Policy.self, forKey: .policy)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
        try container.encode(`protocol`, forKey: .protocol)
        try container.encode(server, forKey: .server)
        try container.encode(features, forKey: .features)
        try container.encode(snapshot, forKey: .snapshot)
        try container.encode(auth, forKey: .auth)
        try container.encode(policy, forKey: .policy)
    }

    public struct Server: Codable, Hashable, Sendable {
        public var version: String
        public var connId: String
        public var buildId: String?

        public init(version: String, connId: String, buildId: String? = nil) {
            self.version = version
            self.connId = connId
            self.buildId = buildId
        }
    }

    /// The methods and events this Gateway supports.
    public struct Features: Codable, Hashable, Sendable {
        public var methods: [String]
        public var events: [String]
        public var capabilities: [String]?

        public init(methods: [String], events: [String], capabilities: [String]? = nil) {
            self.methods = methods
            self.events = events
            self.capabilities = capabilities
        }
    }

    public struct Snapshot: Codable, Hashable, Sendable {
        public var uptimeMs: Int?
        public var stateVersion: StateVersion?
        public var sessionDefaults: SessionDefaults?

        public init(uptimeMs: Int? = nil, stateVersion: StateVersion? = nil, sessionDefaults: SessionDefaults? = nil) {
            self.uptimeMs = uptimeMs
            self.stateVersion = stateVersion
            self.sessionDefaults = sessionDefaults
        }
    }

    public struct SessionDefaults: Codable, Hashable, Sendable {
        public var defaultAgentId: String
        public var mainKey: String
        /// The key of the default agent's main session, such as `agent:main:main`.
        public var mainSessionKey: String

        public init(defaultAgentId: String, mainKey: String, mainSessionKey: String) {
            self.defaultAgentId = defaultAgentId
            self.mainKey = mainKey
            self.mainSessionKey = mainSessionKey
        }
    }

    /// The negotiated role and scopes, plus any device token to persist for later connects.
    public struct Auth: Codable, Hashable, Sendable {
        public var method: AuthMethod?
        public var role: GatewayRole
        public var scopes: [OperatorScope]
        public var deviceToken: String?
        public var issuedAtMs: Int?
        /// Extra tokens issued by a setup-code bootstrap, such as the bounded operator token.
        public var deviceTokens: [IssuedDeviceToken]?

        public init(
            method: AuthMethod? = nil, role: GatewayRole, scopes: [OperatorScope], deviceToken: String? = nil,
            issuedAtMs: Int? = nil, deviceTokens: [IssuedDeviceToken]? = nil
        ) {
            self.method = method
            self.role = role
            self.scopes = scopes
            self.deviceToken = deviceToken
            self.issuedAtMs = issuedAtMs
            self.deviceTokens = deviceTokens
        }
    }

    public struct IssuedDeviceToken: Codable, Hashable, Sendable {
        public var deviceToken: String
        public var role: GatewayRole
        public var scopes: [OperatorScope]
        public var issuedAtMs: Int

        public init(deviceToken: String, role: GatewayRole, scopes: [OperatorScope], issuedAtMs: Int) {
            self.deviceToken = deviceToken
            self.role = role
            self.scopes = scopes
            self.issuedAtMs = issuedAtMs
        }
    }

    /// Connection limits; re-read on every reconnect.
    public struct Policy: Codable, Hashable, Sendable {
        public var maxPayload: Int
        public var maxBufferedBytes: Int
        public var tickIntervalMs: Int
        /// Per-attachment ceilings. Older Gateways omit this.
        public var attachments: AttachmentLimits?

        public init(maxPayload: Int, maxBufferedBytes: Int, tickIntervalMs: Int, attachments: AttachmentLimits? = nil) {
            self.maxPayload = maxPayload
            self.maxBufferedBytes = maxBufferedBytes
            self.tickIntervalMs = tickIntervalMs
            self.attachments = attachments
        }
    }

    public struct AttachmentLimits: Codable, Hashable, Sendable {
        public var maxBytes: Int
        public var maxImageBytes: Int

        public init(maxBytes: Int, maxImageBytes: Int) {
            self.maxBytes = maxBytes
            self.maxImageBytes = maxImageBytes
        }
    }
}

/// How the Gateway authenticated the connection (`hello-ok.auth.method`).
public enum AuthMethod: OpenEnum {
    /// The Gateway runs without authentication (`"none"`).
    case unauthenticated
    case token
    case password
    case tailscale
    case deviceToken
    case bootstrapToken
    case trustedProxy
    case unknown(String)

    public static let knownCases: [AuthMethod] = [
        .unauthenticated, .token, .password, .tailscale, .deviceToken, .bootstrapToken, .trustedProxy,
    ]

    public var rawValue: String {
        switch self {
        case .unauthenticated: "none"
        case .token: "token"
        case .password: "password"
        case .tailscale: "tailscale"
        case .deviceToken: "device-token"
        case .bootstrapToken: "bootstrap-token"
        case .trustedProxy: "trusted-proxy"
        case .unknown(let value): value
        }
    }
}
