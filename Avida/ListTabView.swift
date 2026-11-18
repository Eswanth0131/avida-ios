import SwiftUI

/// The List tab: everything the user saved, from Earn now and Connect next. Swipe to remove.
struct ListTabView: View {
    let store: EarnStore

    var body: some View {
        let items = store.list
        List {
            Section {
                ForEach(items) { item in
                    NavigationLink {
                        destination(for: item)
                    } label: {
                        ListItemRow(item: item)
                    }
                    .listRowBackground(Theme.background)
                    .listRowInsets(EdgeInsets(top: 10, leading: Theme.gutter, bottom: 10, trailing: Theme.gutter))
                    .listRowSeparatorTint(Theme.divider)
                }
                .onDelete { offsets in
                    for index in offsets { store.removeFromList(items[index].id) }
                }
            } header: {
                header(count: items.count)
                    .textCase(nil)
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.gutter, bottom: 12, trailing: Theme.gutter))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .overlay {
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Theme.accent)
                    Text("Nothing here yet")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Tap “Add to List” on an experience in Earn or Connect to keep it here.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark(size: 22)
                .padding(.top, 8)
            Text("My List")
                .font(Theme.display(52))
                .foregroundStyle(Theme.text)
                .padding(.top, 28)
            Text(count == 1 ? "1 experience saved" : "\(count) experiences saved")
                .font(.system(size: 18))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
    }

    /// Earn offers and Connect experiences open their full detail; anything unknown opens the item's own summary.
    @ViewBuilder
    private func destination(for item: ListItem) -> some View {
        switch item.source {
        case .offer(let id):
            if let offer = store.offer(id: id) {
                OfferDetailView(offer: offer, store: store)
            } else {
                ListItemDetailView(item: item, store: store)
            }
        case .connect(let id):
            if let found = ConnectCatalog.lookup(id) {
                ConnectExperienceDetailView(friend: found.friend, experience: found.experience, store: store)
            } else {
                ListItemDetailView(item: item, store: store)
            }
        }
    }
}

struct ListItemRow: View {
    let item: ListItem

    var body: some View {
        HStack(spacing: 16) {
            OfferImage(name: item.imageName, category: item.category, height: 76)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: Theme.photoCorner))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                if let partner = item.partner {
                    Text(partner)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                }
                if let reward = item.reward {
                    Text(reward)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Summary for list items that don't have a richer screen (items from Connect, or offers no longer in the catalog).
struct ListItemDetailView: View {
    let item: ListItem
    let store: EarnStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OfferImage(name: item.imageName, category: item.category, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.top, 8)
                EyebrowText(item.category.rawValue, color: Theme.accent, size: 13)
                    .padding(.top, 24)
                Text(item.title)
                    .lineLimit(2)
                    .font(Theme.display(36))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)
                if let place = item.place {
                    Label(place, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 12)
                }
                if let partner = item.partner {
                    Text(partner)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.top, 24)
                }
                if let reward = item.reward {
                    Text(reward)
                        .font(Theme.serif(26))
                        .foregroundStyle(Theme.text)
                        .padding(.top, 4)
                }
                Text("Added \(item.addedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 16)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Remove from List") {
                store.removeFromList(item.id)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 12)
            .background(Theme.background)
        }
        .avidaChrome()
    }
}
