import Foundation
import Testing
import UIKit
@testable import Avida

struct ConnectTests {
    private let friends = ConnectCatalog.bundled
    private let date = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func mockDataLoads() {
        #expect(friends.map(\.name) == ["Lina", "Ken", "Marion", "Alex"])
        #expect(Set(friends.map(\.id)).count == friends.count)
        for friend in friends {
            #expect((4...5).contains(friend.experiences.count), "\(friend.name) has \(friend.experiences.count) experiences")
            #expect(Set(friend.experiences.map(\.id)).count == friend.experiences.count)
            #expect(friend.experienceCount >= friend.experiences.count)
            #expect(friend.countryCount >= Set(friend.experiences.map(\.country)).count)
            for experience in friend.experiences {
                #expect(experience.stops.count == 3, "\(experience.title)")
                #expect(!experience.description.isEmpty)
            }
        }
    }

    @Test func everyFaceAndPhotoExists() {
        for friend in friends {
            #expect(UIImage(named: friend.face) != nil, "missing face \(friend.face)")
            for name in friend.experiences.compactMap(\.image) {
                #expect(UIImage(named: name) != nil, "missing image \(name)")
            }
        }
    }

    @Test func addedItemsGoToTheListAsConnectFromFriend() throws {
        let lina = try #require(friends.first)
        let amalfi = try #require(lina.experiences.first)
        let item = ListItem.connect(amalfi, from: lina, addedAt: date)
        #expect(item.source == .connect("lina/amalfi-coast"))
        #expect(item.id == "connect:lina/amalfi-coast")
        #expect(item.partner == "From Lina")
        #expect(item.reward == nil)
        #expect(item.title == "Along the Amalfi Coast")
        #expect(item.imageName == "connect-amalfi")

        var state = EarnLogic.toggle(item, in: EarnState())
        #expect(EarnLogic.contains(item.id, in: state))
        state = EarnLogic.toggle(item, in: state)  // "Added ✓" tapped again removes it
        #expect(state.list.isEmpty)
    }

    @Test func sameExperienceFromTwoFriendsIsTwoItems() throws {
        let lina = try #require(friends.first { $0.id == "lina" })
        let marion = try #require(friends.first { $0.id == "marion" })
        let a = ListItem.connect(lina.experiences[0], from: lina, addedAt: date)
        let b = ListItem.connect(marion.experiences[0], from: marion, addedAt: date)
        #expect(a.id != b.id)
    }

    @Test func listItemsLeadBackToTheirExperience() throws {
        let ken = try #require(friends.first { $0.id == "ken" })
        let experience = ken.experiences[1]
        let item = ListItem.connect(experience, from: ken, addedAt: date)
        guard case .connect(let id) = item.source else { Issue.record("wrong source"); return }
        let found = try #require(ConnectCatalog.lookup(id))
        #expect(found.friend.id == "ken")
        #expect(found.experience == experience)
        #expect(ConnectCatalog.lookup("ken/nope") == nil)
        #expect(ConnectCatalog.lookup("garbage") == nil)
    }
}
