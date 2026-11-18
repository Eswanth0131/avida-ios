import Foundation

/// A friend on Connect, from the bundled mock data (connect.json).
nonisolated struct ConnectFriend: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let home: String
    /// Asset catalog name of the round face photo (Assets.xcassets/Connect).
    let face: String
    /// Profile totals ("24 experiences · 6 countries"); the highlights below are their top few.
    let experienceCount: Int
    let countryCount: Int
    let experiences: [ConnectExperience]
}

nonisolated struct ConnectExperience: Codable, Sendable, Hashable, Identifiable {
    let id: String
    let title: String
    let place: String
    let country: String
    let category: ExperienceCategory
    let year: Int
    let description: String
    /// Asset catalog name. Nil: category gradient.
    let image: String?
    let stops: [Offer.Stop]
}

nonisolated enum ConnectCatalog {
    static let bundled: [ConnectFriend] = {
        guard let url = Bundle.main.url(forResource: "connect", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ConnectFriend].self, from: data)) ?? []
    }()

    /// The id a friend's experience has inside ListItem.Source.connect: "<friend>/<experience>".
    static func connectID(friend: ConnectFriend, experience: ConnectExperience) -> String {
        "\(friend.id)/\(experience.id)"
    }

    /// Finds the friend and experience a List item came from.
    static func lookup(_ connectID: String, in friends: [ConnectFriend] = bundled) -> (friend: ConnectFriend, experience: ConnectExperience)? {
        let parts = connectID.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let friend = friends.first(where: { $0.id == parts[0] }),
              let experience = friend.experiences.first(where: { $0.id == parts[1] }) else { return nil }
        return (friend, experience)
    }
}

extension ListItem {
    /// A friend's experience saved from Connect. Shows "From {friend}" where Earn items show the partner.
    nonisolated static func connect(_ experience: ConnectExperience, from friend: ConnectFriend, addedAt: Date) -> ListItem {
        let source = Source.connect(ConnectCatalog.connectID(friend: friend, experience: experience))
        return ListItem(id: id(for: source), source: source, title: experience.title, partner: "From \(friend.name)",
                        reward: nil, place: "\(experience.place), \(experience.country)", category: experience.category,
                        imageName: experience.image, addedAt: addedAt)
    }
}
