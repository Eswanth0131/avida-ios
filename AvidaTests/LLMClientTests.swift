import Foundation
import Testing
@testable import Avida

@MainActor
struct LLMClientTests {
    private let config = LLMConfig(proxyURL: URL(string: "https://proxy.example/v1/messages")!, appToken: "test-token")

    @Test func requestGoesToProxyWithTokenAndNoAPIKey() async throws {
        let transport = FakeTransport(json: #"{"content":[{"type":"text","text":"Hi there"}],"stop_reason":"end_turn"}"#)
        let client = LLMClient(config: config, transport: transport)
        let text = try await client.send(system: "Be brief.", messages: [.user("hello")], maxTokens: 256, effort: "low")
        #expect(text == "Hi there")

        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url == "https://proxy.example/v1/messages")
        #expect(request.method == "POST")
        #expect(request.headers["x-avida-token"] == "test-token")
        #expect(request.headers["x-api-key"] == nil)
        let body = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["model"] as? String == "claude-haiku-5-5")
        #expect(body["max_tokens"] as? Int == 256)
        #expect(body["system"] as? String == "Be brief.")
        #expect((body["output_config"] as? [String: String])?["effort"] == "low")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [["role": "user", "content": "hello"]])
    }

    @Test func parseJoinsTextAndSkipsThinking() throws {
        let json = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"Hello "},{"type":"text","text":"world"}],"stop_reason":"end_turn"}"#
        #expect(try LLMClient.parse(data: Data(json.utf8), status: 200) == "Hello world")
    }

    @Test func parseSurfacesErrorsAndRefusals() {
        let error = #"{"type":"error","error":{"type":"authentication_error","message":"Missing or invalid app token."}}"#
        #expect(throws: LLMError.api(status: 401, type: "authentication_error", message: "Missing or invalid app token.")) {
            try LLMClient.parse(data: Data(error.utf8), status: 401)
        }
        let refusal = #"{"content":[],"stop_reason":"refusal"}"#
        #expect(throws: LLMError.refused) { try LLMClient.parse(data: Data(refusal.utf8), status: 200) }
        #expect(throws: LLMError.emptyResponse) { try LLMClient.parse(data: Data(#"{"content":[]}"#.utf8), status: 200) }
    }

    @Test func missingConfigIsReported() {
        #expect(throws: LLMError.self) { try LLMConfig.load(bundle: Bundle(for: BundleMarker.self)) }
    }
}

private final class BundleMarker {}

/// Records what LLMClient sent and returns a canned reply.
private actor FakeTransport: LLMTransport {
    struct Seen {
        let url: String
        let method: String
        let headers: [String: String]
        let body: Data
    }

    private let json: String
    private(set) var requests: [Seen] = []

    init(json: String) {
        self.json = json
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(Seen(url: request.url?.absoluteString ?? "", method: request.httpMethod ?? "",
                             headers: request.allHTTPHeaderFields ?? [:], body: request.httpBody ?? Data()))
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), response)
    }
}
