import SwiftUI

/// Avida's light theme: cream, charcoal, terracotta.
enum Theme {
    static let background = Color(hex: 0xF9F5EF)
    static let text = Color(hex: 0x2A2826)
    static let secondaryText = Color(hex: 0x7D766E)
    static let accent = Color(hex: 0xB4472E)
    static let divider = Color(hex: 0xE6DED3)
    /// Soft fill for avatars, chips and placeholders.
    static let fill = Color(hex: 0xEEE7DD)

    static let gutter: CGFloat = 24
    static let photoCorner: CGFloat = 12

    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The spaced-out serif "A V I D A".
struct Wordmark: View {
    var size: CGFloat = 20

    var body: some View {
        Text("AVIDA")
            .font(Theme.serif(size))
            .tracking(size * 0.5)
            .foregroundStyle(Theme.text)
            .accessibilityLabel("Avida")
    }
}

/// Uppercase, letter-spaced label: "CULTURE", "184 LIFE EXPERIENCES".
struct EyebrowText: View {
    let text: String
    var color: Color = Theme.secondaryText
    var size: CGFloat = 12

    init(_ text: String, color: Color = Theme.secondaryText, size: CGFloat = 12) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .medium))
            .tracking(size * 0.22)
            .foregroundStyle(color)
    }
}

/// Full-width charcoal button, as in the mockups' bottom actions.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Theme.text.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// "Culinary | Culture | City"
struct CategoryLine: View {
    let categories: [ExperienceCategory]

    var body: some View {
        Text(categories.map(\.rawValue).joined(separator: "  |  "))
            .font(.system(size: 15))
            .foregroundStyle(Theme.secondaryText)
    }
}

extension View {
    /// Cream page with the centred wordmark in the navigation bar.
    func avidaChrome() -> some View {
        self
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Wordmark() }
            }
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension Date {
    /// "Sep 2026"
    var monthYear: String { formatted(.dateTime.month(.abbreviated).year()) }
    /// "2026"
    var yearText: String { formatted(.dateTime.year()) }
}
