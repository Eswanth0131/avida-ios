import Foundation

/// AI is always on (text only). Shown on the Allow Photo Access screen and in Settings.
nonisolated enum AIDisclosure {
    static let line = "Avida uses Claude to write your experience titles. Only text is sent, never photos."
}

/// Proxy URL and app token from Avida/LLMConfig.json (gitignored; see config/LLMConfig.example.json).
/// The Anthropic API key is never in the app: the proxy adds it.
nonisolated struct LLMConfig: Decodable, Sendable {
    let proxyURL: URL
    let appToken: String

    static func load(bundle: Bundle = .main) throws -> LLMConfig {
        guard let url = bundle.url(forResource: "LLMConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            throw LLMError.notConfigured("Avida/LLMConfig.json is missing. Copy config/LLMConfig.example.json, fill in the proxy URL and token, and rebuild.")
        }
        guard let config = try? JSONDecoder().decode(LLMConfig.self, from: data),
              !config.appToken.isEmpty, !config.appToken.hasPrefix("REPLACE"),
              !config.proxyURL.absoluteString.contains("YOUR-SUBDOMAIN") else {
            throw LLMError.notConfigured("Avida/LLMConfig.json still has placeholder values. Fill in the proxy URL and app token.")
        }
        return config
    }
}

nonisolated enum LLMError: LocalizedError, Equatable {
    case notConfigured(String)
    /// Claude or the proxy returned an error object.
    case api(status: Int, type: String, message: String)
    case refused
    case emptyResponse
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message): message
        case .api(let status, let type, let message): "Claude error \(status) (\(type)): \(message)"
        case .refused: "Claude declined to answer this request."
        case .emptyResponse: "Claude returned no text."
        case .transport(let message): "Couldn't reach the proxy: \(message)"
        }
    }
}

/// One text turn. LLMClient only ever sends text; never photos or image data.
nonisolated struct LLMMessage: Codable, Sendable, Equatable {
    let role: String
    let content: String

    static func user(_ text: String) -> LLMMessage { LLMMessage(role: "user", content: text) }
    static func assistant(_ text: String) -> LLMMessage { LLMMessage(role: "assistant", content: text) }
}

/// Sends one HTTP request. A protocol (not a closure) so tests can fake it without
/// cross-module closure-isolation differences: the app target defaults to main-actor isolation, the tests don't.
nonisolated protocol LLMTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

nonisolated struct URLSessionTransport: LLMTransport {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

/// Any JSON value. Used for Messages API bodies with tool use, where assistant content blocks
/// (including thinking blocks) must be sent back exactly as received.
nonisolated enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    var intValue: Int? { if case .number(let value) = self, value.rounded() == value { Int(value) } else { nil } }
    var arrayValue: [JSONValue]? { if case .array(let value) = self { value } else { nil } }

    /// Compact JSON text with sorted keys (stable, so tests and the request log are deterministic).
    var compactJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "null"
    }
}

/// The exact body of the most recent request sent to the proxy, for Developer → Show last request.
@Observable
final class LLMRequestLog {
    static let shared = LLMRequestLog()

    private(set) var lastBody: String?
    private(set) var lastDate: Date?

    func record(_ body: Data) {
        lastBody = String(decoding: body, as: UTF8.self)
        lastDate = .now
    }
}

/// Calls Claude through the Avida proxy (tools/proxy). This is the app's only network path for derived data,
/// and it only ever sends text.
final class LLMClient {
    nonisolated static let model = "claude-haiku-5-5"

    /// Nil means read Avida/LLMConfig.json from the app bundle at call time.
    private let config: LLMConfig?
    private let transport: any LLMTransport
    private let log: LLMRequestLog

    init(
        config: LLMConfig? = nil,
        transport: any LLMTransport = URLSessionTransport(),
        log: LLMRequestLog = .shared
    ) {
        self.config = config
        self.transport = transport
        self.log = log
    }

    /// Sends a Messages API body as-is (the proxy adds the API key) and returns the decoded reply.
    func createMessage(_ body: JSONValue) async throws -> JSONValue {
        let config = try config ?? LLMConfig.load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bodyData = try encoder.encode(body)
        let request = Self.makeRequest(config: config, body: bodyData)

        log.record(bodyData)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }
        return try Self.decodeReply(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// Sends text and returns Claude's text reply.
    func send(system: String? = nil, messages: [LLMMessage], maxTokens: Int = 2048, effort: String? = nil) async throws -> String {
        var body: [String: JSONValue] = [
            "model": .string(Self.model),
            "max_tokens": .number(Double(maxTokens)),
            "messages": .array(messages.map { .object(["role": .string($0.role), "content": .string($0.content)]) }),
        ]
        if let system { body["system"] = .string(system) }
        if let effort { body["output_config"] = .object(["effort": .string(effort)]) }
        return try Self.text(of: try await createMessage(.object(body)))
    }

    nonisolated static func makeRequest(config: LLMConfig, body: Data) -> URLRequest {
        // Long JSON replies (titles for 40 experiences) can take longer than a minute on a slow connection.
        var request = URLRequest(url: config.proxyURL, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(config.appToken, forHTTPHeaderField: "x-avida-token")
        request.httpBody = body
        return request
    }

    /// Turns error statuses into `LLMError.api` (Claude and the proxy share one error shape), else decodes the reply.
    nonisolated static func decodeReply(data: Data, status: Int) throws -> JSONValue {
        guard (200..<300).contains(status) else {
            let reply = try? JSONDecoder().decode(JSONValue.self, from: data)
            if let type = reply?["error"]?["type"]?.stringValue, let message = reply?["error"]?["message"]?.stringValue {
                throw LLMError.api(status: status, type: type, message: message)
            }
            throw LLMError.api(status: status, type: "unknown", message: String(decoding: data.prefix(300), as: UTF8.self))
        }
        guard let reply = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw LLMError.emptyResponse }
        if reply["stop_reason"]?.stringValue == "refusal" { throw LLMError.refused }
        return reply
    }

    /// Joins the reply's text blocks. Thinking blocks (Haiku 5.5 thinks by default) are ignored.
    nonisolated static func text(of reply: JSONValue) throws -> String {
        let text = (reply["content"]?.arrayValue ?? [])
            .filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LLMError.emptyResponse }
        return text
    }

    nonisolated static func parse(data: Data, status: Int) throws -> String {
        try text(of: decodeReply(data: data, status: status))
    }
}
