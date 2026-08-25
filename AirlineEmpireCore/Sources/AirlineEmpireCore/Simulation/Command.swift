/// Commands are the only player/AI mutation path (docs/ARCHITECTURE.md §3.2).
/// Each command validates against current state; rejected commands change
/// nothing and explain why in UI-presentable terms.
public protocol Command: Codable, Sendable {
    /// Stable name for serialization (command log, replay) and diagnostics.
    /// Registered in a `CommandRegistry`; never renamed once shipped.
    static var name: String { get }

    /// Returns nil when the command may apply to this state.
    func validate(state: GameState) -> CommandRejection?

    /// Applies the command. Called only after `validate` returned nil in the
    /// same tick; must uphold all invariants.
    func apply(state: inout GameState, context: SimContext)
}

/// A typed, user-presentable refusal. Codes are stable API for the UI;
/// messages are developer-readable defaults the UI may replace.
public struct CommandRejection: Equatable, Codable, Sendable, Error {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public enum CommandResult: Equatable, Sendable {
    case applied
    case rejected(CommandRejection)
}

/// Decodes heterogeneous commands for the command log/replay by stable name.
/// Built at the composition root; no global registry (banned global state).
public struct CommandRegistry: Sendable {
    private var decoders: [String: @Sendable (Decoder) throws -> any Command]

    public init() {
        decoders = [:]
    }

    public mutating func register<C: Command>(_ type: C.Type) {
        precondition(decoders[C.name] == nil, "Duplicate command name: \(C.name)")
        decoders[C.name] = { decoder in try C(from: decoder) }
    }

    public func decoder(for name: String) -> (@Sendable (Decoder) throws -> any Command)? {
        decoders[name]
    }
}

/// Envelope for serializing `any Command` with its stable name.
public struct CommandEnvelope: Codable, Sendable {
    public let name: String
    public let command: any Command

    enum CodingKeys: String, CodingKey { case name, payload }

    public init(_ command: any Command) {
        self.name = type(of: command).name
        self.command = command
    }

    public init(from decoder: Decoder) throws {
        guard let registry = decoder.userInfo[CommandRegistry.userInfoKey] as? CommandRegistry else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "CommandRegistry missing from decoder userInfo"))
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        guard let decode = registry.decoder(for: name) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown command name: \(name)"))
        }
        self.name = name
        self.command = try decode(try container.superDecoder(forKey: .payload))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try command.encode(to: container.superEncoder(forKey: .payload))
    }
}

extension CommandRegistry {
    public static let userInfoKey = CodingUserInfoKey(rawValue: "AirlineEmpire.CommandRegistry")!
}
