import SwiftUI

/// The first launch: what this app does, what to try first, and where things are (the Sherpa's journey
/// for a new tester, website/journeys/). Shown once; the Guide holds the same and more.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let lines: [String]
    }

    private let pages = [
        Page(id: 0, symbol: "waveform", title: "A voice note in, a debrief out",
             lines: ["Record a note. It is saved as you speak, so nothing is lost if you are interrupted.",
                     "When you finish, it is transcribed and summarised on this device by Apple's own models. Nothing is sent anywhere unless you send it."]),
        Page(id: 1, symbol: "mic.circle", title: "Try this first",
             lines: ["On the Record tab, check the language you will speak in.",
                     "Tap the green button, speak for ten seconds, and tap it again.",
                     "The note opens and fills in: the transcript, then the debrief."]),
        Page(id: 2, symbol: "map", title: "Where things are",
             lines: ["Record: start a note. Library: every note. Vaults: keep notes encrypted, on this device or a server. Settings: language, recipients, identity.",
                     "Guide: what is new in each version, every idea and where it stands, and a picture guide to each feature.",
                     "This is a test build: the balance at the top is test credit, and no money is taken."]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages) { p in
                    ScrollView {
                        VStack(spacing: 18) {
                            Image(systemName: p.symbol).font(.system(size: 56)).foregroundStyle(Color.accentColor)
                                .padding(.top, 48)
                            Text(p.title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(p.lines, id: \.self) { Text($0) }
                            }
                            .frame(maxWidth: 480, alignment: .leading)
                        }
                        .padding(.horizontal, 24)
                    }
                    .tag(p.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 { withAnimation { page += 1 } } else { dismiss() }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Start").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            Button("Skip") { dismiss() }
                .padding(.bottom, 16)
                .opacity(page < pages.count - 1 ? 1 : 0)
        }
    }
}

enum WelcomeMemory {
    static let key = "vd.guide.welcomed"
}

private struct WelcomeOnFirstLaunch: ViewModifier {
    @AppStorage(WelcomeMemory.key) private var welcomed = false
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showing, onDismiss: { welcomed = true }) { WelcomeView() }
            .onAppear {
                // Never over the pictures of the screens: a sample launch is not a first launch.
                guard !welcomed, LaunchOptions.sampleSet() == nil else { return }
                showing = true
                WhatsNewMemory.seedIfNeeded()
            }
    }
}

extension View {
    /// Shows the welcome once, on the first launch, and starts remembering which versions were seen.
    func welcomeOnFirstLaunch() -> some View { modifier(WelcomeOnFirstLaunch()) }
}
