import Foundation

/// The Ask bar's agent: Claude answers questions by calling ExperienceTools, which run on the device.
/// Only the tools' text results are sent; no photos, image data or file paths.
final class AskAgent {
    nonisolated static let maxToolRounds = 5

    nonisolated static let systemPrompt = """
    You answer questions about the user's own life experiences, recorded in the Avida app from their photos. \
    Use the tools to look things up before answering.
    Rules:
    - Answer only from tool results. Never invent places, events, dates, people or details the tools didn't return. \
    If the tools don't have the answer, say so briefly.
    - Keep the answer to 2–4 sentences, speaking to the user as "you".
    - Refer to an experience only by its id in square brackets, for example "your trip [e3]". \
    The app replaces the id with the experience's title and links it, so don't also write the title.
    - For what to do next, call list_suggestions and recommend one or two that fit what the user already loves \
    (their categories and places), by id: Earn experiences are [o1], [o2]…, friends' experiences are [c1], [c2]….
    """

    private let client: LLMClient
    private let tools: ExperienceTools
    private let maxTokens: Int

    init(client: LLMClient, tools: ExperienceTools, maxTokens: Int = 2048) {
        self.client = client
        self.tools = tools
        self.maxTokens = maxTokens
    }

    struct Answer: Equatable {
        let text: String
        /// Tool names in the order they were called.
        let toolsUsed: [String]
        /// True when the round limit was hit and Claude had to answer without more tools.
        let hitRoundLimit: Bool
    }

    func ask(_ question: String) async throws -> Answer {
        var messages: [JSONValue] = [.object(["role": .string("user"), "content": .string(question)])]
        var toolsUsed: [String] = []

        for round in 1...(Self.maxToolRounds + 1) {
            let isFinalRound = round > Self.maxToolRounds
            let reply = try await client.createMessage(body(messages: messages, allowTools: !isFinalRound))
            let content = reply["content"]?.arrayValue ?? []
            let toolCalls = content.filter { $0["type"]?.stringValue == "tool_use" }

            if toolCalls.isEmpty || isFinalRound {
                return Answer(text: try LLMClient.text(of: reply), toolsUsed: toolsUsed, hitRoundLimit: isFinalRound)
            }

            // Echo the assistant turn back exactly (thinking blocks included), then the tool results.
            messages.append(.object(["role": .string("assistant"), "content": .array(content)]))
            var results: [JSONValue] = toolCalls.map { call in
                let name = call["name"]?.stringValue ?? ""
                toolsUsed.append(name)
                let result = tools.run(name: name, input: call["input"] ?? .object([:]))
                var block: [String: JSONValue] = [
                    "type": .string("tool_result"),
                    "tool_use_id": call["id"] ?? .string(""),
                    "content": .string(result.json),
                ]
                if result.isError { block["is_error"] = .bool(true) }
                return .object(block)
            }
            if round == Self.maxToolRounds {
                results.append(.object([
                    "type": .string("text"),
                    "text": .string("That's the last tool round. Answer now from the results above."),
                ]))
            }
            messages.append(.object(["role": .string("user"), "content": .array(results)]))
        }
        throw LLMError.emptyResponse  // unreachable: the final round always returns or throws
    }

    /// After the round limit, tools stay declared (the history references them) but tool_choice "none" forces text.
    private func body(messages: [JSONValue], allowTools: Bool) -> JSONValue {
        var body: [String: JSONValue] = [
            "model": .string(LLMClient.model),
            "max_tokens": .number(Double(maxTokens)),
            "system": .string(Self.systemPrompt),
            "tools": ExperienceTools.definitions,
            "messages": .array(messages),
        ]
        if !allowTools { body["tool_choice"] = .object(["type": .string("none")]) }
        return .object(body)
    }
}

/// Splits an answer into text and [eN] references for linking.
nonisolated enum AskAnswerText {
    enum Part: Equatable {
        case text(String)
        /// e1… (the user's experiences), o1… (Earn), c1… (Connect)
        case experience(String)
    }

    static func parts(_ answer: String) -> [Part] {
        var parts: [Part] = []
        var rest = Substring(answer)
        while let match = rest.firstMatch(of: /\[([eoc]\d+)\]/) {
            let before = rest[rest.startIndex..<match.range.lowerBound]
            if !before.isEmpty { parts.append(.text(String(before))) }
            parts.append(.experience(String(match.output.1)))
            rest = rest[match.range.upperBound...]
        }
        if !rest.isEmpty { parts.append(.text(String(rest))) }
        return parts
    }
}
