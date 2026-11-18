import SwiftUI
import Photos

/// Flow (as in Step 4): allow access → analyzing → review → "Create my profile" → tabs, opening on Profile.
/// Light theme only.
struct ContentView: View {
    @State private var model = AppModel()
    @State private var showProfile = false

    var body: some View {
        Group {
            if showProfile, model.hasAccess, model.isReady {
                MainTabView(model: model) { showProfile = false }
            } else {
                NavigationStack { content }
            }
        }
        .tint(Theme.text)
        .preferredColorScheme(.light)
        .task(id: model.status) {
            if model.hasAccess { await model.scan() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .notDetermined:
            WelcomeView { Task { await model.requestAccess() } }
        case .authorized, .limited:
            if !model.isReady {
                AnalyzingView(model: model)
            } else {
                ReviewView(model: model) { showProfile = true }
            }
        default:
            MessageView(
                title: "Avida needs your photos.",
                message: "Allow access to your photos so Avida can find the experiences you've lived. Your photos stay on this iPhone.",
                action: ("Open Settings", {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                })
            )
        }
    }
}

/// "Let Avida read your life."
private struct WelcomeView: View {
    let onAllow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark(size: 18)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            Spacer()
            Text("Let Avida\nread your life.")
                .font(Theme.serif(44))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 36)
            VStack(alignment: .leading, spacing: 24) {
                feature("photo.on.rectangle", "Find your experiences", "Places and moments, found in your photos.")
                feature("lock", "Keep it private", "Everything runs on this iPhone. Nothing is uploaded.")
                feature("book.closed", "Build your life profile", "Only what's worth remembering, ranked.")
            }
            Spacer()
            Button("Allow Photo Access", action: onAllow)
                .buttonStyle(PrimaryButtonStyle())
            Text("Avida reads the camera photos in your library, on this iPhone.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            Text(AIDisclosure.line)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .background(Theme.background.ignoresSafeArea())
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 15)).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// "Analyzing your photos." with a progress ring while scanning and tagging run.
private struct AnalyzingView: View {
    let model: AppModel

    /// The whole scan: reading, tagging, then titles. 100% only when experiences are ready.
    private var progress: Double { model.progress }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark(size: 18)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            Text("Analyzing\nyour photos.")
                .font(Theme.serif(44))
                .foregroundStyle(Theme.text)
                .padding(.top, 48)
            Text(model.isWritingTitles ? "Writing your titles…" : "Finding the experiences you've lived…")
                .font(.system(size: 17))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 12)
            Spacer()
            ZStack {
                Circle().stroke(Theme.fill, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut, value: progress)
                Text("\(Int(progress * 100))%")
                    .font(Theme.serif(40, weight: .light))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
            }
            .frame(width: 180, height: 180)
            .frame(maxWidth: .infinity)
            Spacer()
            HStack {
                counter(model.summary?.photoCount, "Photos")
                counter(model.clusters.map { $0.trips.flatMap(\.moments).count + $0.otherMoments.count }, "Moments")
                counter(model.clusters.map { _ in model.experiences.count }, "Experiences")
            }
            .padding(.vertical, 20)
            .overlay(alignment: .top) { Rectangle().fill(Theme.divider).frame(height: 1) }
            Text(statusLine)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .background(Theme.background.ignoresSafeArea())
    }

    /// Scan → tagging → (AI on) titles.
    private var statusLine: String {
        if model.isWritingTitles { return "Writing your titles…" }
        if model.tagging.isRunning { return "Looking closely at \(model.tagging.done) of \(model.tagging.total) photos" }
        if model.isLimited { return "Reading the photos you selected…" }
        return "Reading your photo library…"
    }

    private func counter(_ value: Int?, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value.map(String.init) ?? "—")
                .font(Theme.serif(28))
                .foregroundStyle(Theme.text)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Full-screen message with one action, for missing access or a missing album.
private struct MessageView: View {
    let title: String
    let message: String
    let action: (label: String, run: () -> Void)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Wordmark(size: 18)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            Spacer()
            Text(title)
                .font(Theme.display(34))
                .foregroundStyle(Theme.text)
            Text(message)
                .font(.system(size: 17))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Button(action.label, action: action.run)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.bottom, 12)
        .background(Theme.background.ignoresSafeArea())
    }
}

#Preview {
    ContentView()
}
