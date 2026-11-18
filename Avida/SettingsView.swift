import SwiftUI
import CoreLocation

/// Profile → Settings: name and home, plus how Avida uses Claude (AI is always on, text only).
struct SettingsView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var locator = LocationFetcher()
    @State private var homeMessage: String?
    @State private var isLocating = false

    private var prefs: UserPrefs { model.prefs }

    var body: some View {
        @Bindable var prefs = model.prefs
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.text)
                    .padding(.top, 8)
                    .padding(.bottom, 24)

                section("Your name") {
                    TextField("Your name", text: $prefs.userName)
                        .font(.system(size: 19))
                        .textContentType(.givenName)
                        .submitLabel(.done)
                    Text("Shown on your profile. Leave empty to show “Your profile”.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                }

                section("Home") {
                    Text(homeLine)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(homeSourceLine)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                    HStack(spacing: 18) {
                        Button(isLocating ? "Locating…" : "Use my current location") {
                            Task { await useCurrentLocation() }
                        }
                        .disabled(isLocating)
                        if prefs.homeOverride != nil {
                            Button("Detect from my photos") {
                                prefs.homeOverride = nil
                                homeMessage = nil
                                Task { await model.scan() }
                            }
                        }
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 4)
                    if let homeMessage {
                        Text(homeMessage)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.accent)
                    }
                }

                section("Claude") {
                    Text(AIDisclosure.line)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
        .avidaChrome()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EyebrowText(title, size: 12)
            content()
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }

    private var homeLine: String {
        guard let city = model.homeCity else { return "Not set yet" }
        return "\(city.name), \(PlaceLookup.countryName(city.countryCode))"
    }

    private var homeSourceLine: String {
        switch model.summary?.homeSource {
        case .setByUser: "Set by you. Trips are measured from here."
        case .detected: "Detected from where your photos are taken most often. Trips are measured from here."
        case .some(HomeSource.none), nil: "Detected from your photos once they have locations."
        }
    }

    /// Sets home to where the phone is now, then rebuilds experiences with it.
    private func useCurrentLocation() async {
        isLocating = true
        defer { isLocating = false }
        do {
            let location = try await locator.currentLocation()
            model.prefs.homeOverride = HomeOverride(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            homeMessage = nil
            await model.scan()
        } catch {
            homeMessage = error.localizedDescription
        }
    }
}
