import SwiftUI

/// "We found N experiences." Ranked cards, then a button to the profile.
struct ReviewView: View {
    let model: AppModel
    let onContinue: () -> Void

    var body: some View {
        let experiences = model.experiences
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("We found \(experiences.count) \(experiences.count == 1 ? "experience" : "experiences").")
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 16)
                Text(experiences.isEmpty
                     ? "Avida groups photos that have a location. Take photos with Location Services on for the Camera, then rescan from Developer."
                     : "Here are the highlights, most memorable first. Review them before creating your profile.")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.secondaryText)
                    .lineSpacing(3)
                    .padding(.top, 14)
                    .padding(.bottom, model.isLimited ? 8 : 20)

                if model.isLimited {
                    Text("Avida can see only the photos you selected. To find experiences across your whole library, allow Full Access in Settings → Avida → Photos.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.accent)
                        .padding(.bottom, 20)
                }

                ForEach(experiences) { experience in
                    NavigationLink {
                        ExperienceDetailView(experience: experience)
                    } label: {
                        ReviewCard(experience: experience)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Text("Create my profile")
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 12)
            .background(Theme.background)
        }
        .avidaChrome()
    }
}

private struct ReviewCard: View {
    let experience: Experience

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(experience.title)
                        .lineLimit(2)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                    Text("\(experience.place)  ·  \(experience.start.monthYear)")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                Label("Only me", systemImage: "lock")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .labelStyle(.titleAndIcon)
                    .padding(.top, 3)
            }

            HStack(spacing: 8) {
                ForEach(experience.coverIDs, id: \.self) { id in
                    Thumbnail(id: id, pointSide: 130)
                        .frame(maxWidth: .infinity)
                        .frame(height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.photoCorner))
                }
            }

            Rectangle().fill(Theme.divider).frame(height: 1)

            HStack {
                CategoryLine(categories: experience.categories)
                Spacer()
                HStack(spacing: 4) {
                    Text("Review")
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                }
                .font(.system(size: 17))
                .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 22)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}
