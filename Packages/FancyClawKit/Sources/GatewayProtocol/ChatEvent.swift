/// The payload of a `chat` event: one step of a run's assistant output, discriminated on `state`.
public struct ChatEvent: Hashable, Sendable {
    public var runId: String
    public var sessionKey: String
    /// Per-run ordering; use it to drop duplicate or stale deltas.
    public var seq: Int
    public var agentId: String?
    public var spawnedBy: String?
    public var state: State
    public var usage: JSONValue?

    public init(
        runId: String, sessionKey: String, seq: Int, agentId: String? = nil, spawnedBy: String? = nil,
        state: State, usage: JSONValue? = nil
    ) {
        self.runId = runId
        self.sessionKey = sessionKey
        self.seq = seq
        self.agentId = agentId
        self.spawnedBy = spawnedBy
        self.state = state
        self.usage = usage
    }

    public enum State: Hashable, Sendable {
        case status(Status)
        case delta(Delta)
        case final(Final)
        case aborted(Aborted)
        case error(Failure)
        /// A state introduced by a newer Gateway.
        case unknown(String)
    }

    /// Progress before the model starts streaming.
    public struct Status: Hashable, Sendable {
        public var phase: ChatRunPhase?
        public var retry: Retry?

        public init(phase: ChatRunPhase?, retry: Retry? = nil) {
            self.phase = phase
            self.retry = retry
        }
    }

    public struct Retry: Codable, Hashable, Sendable {
        public var attempt: Int
        public var maxAttempts: Int
        public var reason: String

        public init(attempt: Int, maxAttempts: Int, reason: String) {
            self.attempt = attempt
            self.maxAttempts = maxAttempts
            self.reason = reason
        }
    }

    /// New assistant text.
    ///
    /// Append `deltaText` to the buffer, unless ``isReplacement`` is true, in which case `deltaText` replaces
    /// the buffer. `message`, when present, is the cumulative assistant snapshot.
    public struct Delta: Hashable, Sendable {
        public var deltaText: String
        public var replace: Bool?
        public var message: ChatMessage?

        public init(deltaText: String, replace: Bool? = nil, message: ChatMessage? = nil) {
            self.deltaText = deltaText
            self.replace = replace
            self.message = message
        }

        public var isReplacement: Bool { replace ?? false }
    }

    public struct Final: Hashable, Sendable {
        public var message: ChatMessage?
        public var stopReason: String?
        public var yielded: Bool?

        public init(message: ChatMessage? = nil, stopReason: String? = nil, yielded: Bool? = nil) {
            self.message = message
            self.stopReason = stopReason
            self.yielded = yielded
        }
    }

    public struct Aborted: Hashable, Sendable {
        public var message: ChatMessage?
        public var errorMessage: String?
        public var stopReason: String?

        public init(message: ChatMessage? = nil, errorMessage: String? = nil, stopReason: String? = nil) {
            self.message = message
            self.errorMessage = errorMessage
            self.stopReason = stopReason
        }
    }

    public struct Failure: Hashable, Sendable {
        public var message: ChatMessage?
        public var errorMessage: String?
        public var errorKind: ChatErrorKind?
        public var errorDetail: ErrorDetail?
        public var stopReason: String?

        public init(
            message: ChatMessage? = nil, errorMessage: String? = nil, errorKind: ChatErrorKind? = nil,
            errorDetail: ErrorDetail? = nil, stopReason: String? = nil
        ) {
            self.message = message
            self.errorMessage = errorMessage
            self.errorKind = errorKind
            self.errorDetail = errorDetail
            self.stopReason = stopReason
        }
    }

    /// Sanitized provider facts about a failed attempt.
    public struct ErrorDetail: Codable, Hashable, Sendable {
        public var provider: String?
        public var model: String?
        public var failoverReason: String?
        public var providerRuntimeFailureKind: String?
        public var providerErrorType: String?
        public var httpStatus: Int?
        public var providerErrorMessagePreview: String?

        public init(
            provider: String? = nil, model: String? = nil, failoverReason: String? = nil,
            providerRuntimeFailureKind: String? = nil, providerErrorType: String? = nil, httpStatus: Int? = nil,
            providerErrorMessagePreview: String? = nil
        ) {
            self.provider = provider
            self.model = model
            self.failoverReason = failoverReason
            self.providerRuntimeFailureKind = providerRuntimeFailureKind
            self.providerErrorType = providerErrorType
            self.httpStatus = httpStatus
            self.providerErrorMessagePreview = providerErrorMessagePreview
        }
    }
}

extension ChatEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case runId, sessionKey, seq, agentId, spawnedBy, state, usage
        case phase, retry, deltaText, replace, message, stopReason, yielded, errorMessage, errorKind, errorDetail
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runId = try container.decode(String.self, forKey: .runId)
        sessionKey = try container.decode(String.self, forKey: .sessionKey)
        seq = try container.decode(Int.self, forKey: .seq)
        agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
        spawnedBy = try container.decodeIfPresent(String.self, forKey: .spawnedBy)
        usage = try container.decodeIfPresent(JSONValue.self, forKey: .usage)

        let message = { try container.decodeIfPresent(ChatMessage.self, forKey: .message) }
        let stopReason = { try container.decodeIfPresent(String.self, forKey: .stopReason) }
        let errorMessage = { try container.decodeIfPresent(String.self, forKey: .errorMessage) }

        switch try container.decode(String.self, forKey: .state) {
        case "status":
            state = .status(Status(
                phase: try container.decodeIfPresent(ChatRunPhase.self, forKey: .phase),
                retry: try container.decodeIfPresent(Retry.self, forKey: .retry)))
        case "delta":
            state = .delta(Delta(
                deltaText: try container.decodeIfPresent(String.self, forKey: .deltaText) ?? "",
                replace: try container.decodeIfPresent(Bool.self, forKey: .replace),
                message: try message()))
        case "final":
            state = .final(Final(
                message: try message(), stopReason: try stopReason(),
                yielded: try container.decodeIfPresent(Bool.self, forKey: .yielded)))
        case "aborted":
            state = .aborted(Aborted(message: try message(), errorMessage: try errorMessage(), stopReason: try stopReason()))
        case "error":
            state = .error(Failure(
                message: try message(), errorMessage: try errorMessage(),
                errorKind: try container.decodeIfPresent(ChatErrorKind.self, forKey: .errorKind),
                errorDetail: try container.decodeIfPresent(ErrorDetail.self, forKey: .errorDetail),
                stopReason: try stopReason()))
        case let other:
            state = .unknown(other)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(runId, forKey: .runId)
        try container.encode(sessionKey, forKey: .sessionKey)
        try container.encode(seq, forKey: .seq)
        try container.encodeIfPresent(agentId, forKey: .agentId)
        try container.encodeIfPresent(spawnedBy, forKey: .spawnedBy)
        try container.encodeIfPresent(usage, forKey: .usage)

        switch state {
        case .status(let status):
            try container.encode("status", forKey: .state)
            try container.encodeIfPresent(status.phase, forKey: .phase)
            try container.encodeIfPresent(status.retry, forKey: .retry)
        case .delta(let delta):
            try container.encode("delta", forKey: .state)
            try container.encode(delta.deltaText, forKey: .deltaText)
            try container.encodeIfPresent(delta.replace, forKey: .replace)
            try container.encodeIfPresent(delta.message, forKey: .message)
        case .final(let final):
            try container.encode("final", forKey: .state)
            try container.encodeIfPresent(final.message, forKey: .message)
            try container.encodeIfPresent(final.stopReason, forKey: .stopReason)
            try container.encodeIfPresent(final.yielded, forKey: .yielded)
        case .aborted(let aborted):
            try container.encode("aborted", forKey: .state)
            try container.encodeIfPresent(aborted.message, forKey: .message)
            try container.encodeIfPresent(aborted.errorMessage, forKey: .errorMessage)
            try container.encodeIfPresent(aborted.stopReason, forKey: .stopReason)
        case .error(let failure):
            try container.encode("error", forKey: .state)
            try container.encodeIfPresent(failure.message, forKey: .message)
            try container.encodeIfPresent(failure.errorMessage, forKey: .errorMessage)
            try container.encodeIfPresent(failure.errorKind, forKey: .errorKind)
            try container.encodeIfPresent(failure.errorDetail, forKey: .errorDetail)
            try container.encodeIfPresent(failure.stopReason, forKey: .stopReason)
        case .unknown(let state):
            try container.encode(state, forKey: .state)
        }
    }
}

/// What a run is doing before the model streams (`chat` status `phase`).
public enum ChatRunPhase: OpenEnum {
    case preparingWorkspace
    case namingWorktree
    case creatingWorktree
    case runningSetup
    case provisioningEnvironment
    case preparingContext
    case memoryFlushing
    case startingModel
    case unknown(String)

    public static let knownCases: [ChatRunPhase] = [
        .preparingWorkspace, .namingWorktree, .creatingWorktree, .runningSetup, .provisioningEnvironment,
        .preparingContext, .memoryFlushing, .startingModel,
    ]

    public var rawValue: String {
        switch self {
        case .preparingWorkspace: "preparing_workspace"
        case .namingWorktree: "naming_worktree"
        case .creatingWorktree: "creating_worktree"
        case .runningSetup: "running_setup"
        case .provisioningEnvironment: "provisioning_environment"
        case .preparingContext: "preparing_context"
        case .memoryFlushing: "memory_flushing"
        case .startingModel: "starting_model"
        case .unknown(let value): value
        }
    }
}

/// The coarse failure category of a `chat` error, used to pick user-facing copy.
public enum ChatErrorKind: OpenEnum {
    case refusal
    case timeout
    case rateLimit
    case contextLength
    /// The Gateway couldn't classify the failure (`"unknown"` on the wire).
    case unclassified
    case unknown(String)

    public static let knownCases: [ChatErrorKind] = [.refusal, .timeout, .rateLimit, .contextLength, .unclassified]

    public var rawValue: String {
        switch self {
        case .refusal: "refusal"
        case .timeout: "timeout"
        case .rateLimit: "rate_limit"
        case .contextLength: "context_length"
        case .unclassified: "unknown"
        case .unknown(let value): value
        }
    }
}
