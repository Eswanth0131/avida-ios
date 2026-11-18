import SwiftUI

/// Where a tapped link in an answer goes.
enum AskTarget: Hashable {
    case photos(Experience)
    case verified(VerifiedExperience)
    case offer(Offer)
    case connect(ConnectFriend, ConnectExperience)
}

/// Profile's Ask section: five prefilled questions (no free text) and the answer card.
struct AskBarView: View {
    let model: AppModel
    @Binding var target: AskTarget?

    @State private var asked: String?
    @State private var isAsking = false
    @State private var answer: AskAgent.Answer?
    @State private var errorText: String?
    @State private var records: [ExperienceRecord] = []
    @State private var suggestions: [SuggestionRecord] = []

    static let questions = [
        "What defines me?",
        "My rarest experiences",
        "Where have I been?",
        "My most memorable trip",
        "What should I do next?",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                EyebrowText("Ask about your life", color: Theme.text, size: 13)
            }
            .foregroundStyle(Theme.text)

            VStack(spacing: 0) {
                ForEach(Self.questions, id: \.self) { question in
                    Button { ask(question) } label: {
                        HStack {
                            Text(question)
                                .font(.system(size: 17))
                                .foregroundStyle(asked == question ? Theme.accent : Theme.text)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isAsking)
                    if question != Self.questions.last {
                        Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 18)
                    }
                }
            }
            .background(cardBackground)

            if asked != nil { answerCard }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.55))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.divider, lineWidth: 1))
    }

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(asked ?? "")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Button {
                    asked = nil
                    answer = nil
                    errorText = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel("Close answer")
                .disabled(isAsking)
            }

            if isAsking {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking through your experiences…")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondaryText)
                }
            } else if let errorText {
                Text(errorText)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accent)
            } else if let answer {
                Text(linkedText(answer.text))
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3)
                    .environment(\.openURL, OpenURLAction { url in
                        open(url)
                        return .handled
                    })
                if !answer.toolsUsed.isEmpty {
                    Text("Looked up: \(answer.toolsUsed.joined(separator: ", "))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(18)
        .background(cardBackground)
    }

    /// Replaces [eN] / [oN] / [cN] with that item's title as a terracotta link. Unknown ids are dropped.
    private func linkedText(_ text: String) -> AttributedString {
        var result = AttributedString()
        for part in AskAnswerText.parts(text) {
            switch part {
            case .text(let string):
                result += AttributedString(string)
            case .experience(let id):
                guard let title = title(for: id) else { continue }
                var link = AttributedString(title)
                link.link = URL(string: "avida-ask://item/\(id)")
                link.foregroundColor = Theme.accent
                link.underlineStyle = .single
                result += link
            }
        }
        return result
    }

    private func title(for id: String) -> String? {
        records.first { $0.id == id }?.title ?? suggestions.first { $0.id == id }?.title
    }

    private func open(_ url: URL) {
        guard url.scheme == "avida-ask" else { return }
        let id = url.lastPathComponent
        if let record = records.first(where: { $0.id == id }) {
            switch record.source {
            case .photos(let experienceID):
                if let experience = model.experiences.first(where: { $0.id == experienceID }) { target = .photos(experience) }
            case .verified(let verifiedID):
                if let verified = model.earn.verified.first(where: { $0.id == verifiedID }) { target = .verified(verified) }
            }
        } else if let suggestion = suggestions.first(where: { $0.id == id }) {
            switch suggestion.target {
            case .offer(let offerID):
                if let offer = model.earn.offer(id: offerID) { target = .offer(offer) }
            case .connect(let connectID):
                if let found = ConnectCatalog.lookup(connectID) { target = .connect(found.friend, found.experience) }
            }
        }
    }

    private func ask(_ question: String) {
        guard !isAsking else { return }
        asked = question
        answer = nil
        errorText = nil
        isAsking = true
        let snapshot = ExperienceTools.snapshot(experiences: model.experiences, verified: model.earn.verified,
                                                rarity: model.rarityScores)
        let nextUp = ExperienceTools.suggestions(offers: model.earn.offers, friends: ConnectCatalog.bundled)
        records = snapshot
        suggestions = nextUp
        Task {
            defer { isAsking = false }
            do {
                let tools = ExperienceTools(records: snapshot, suggestions: nextUp)
                answer = try await AskAgent(client: LLMClient(), tools: tools).ask(question)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
