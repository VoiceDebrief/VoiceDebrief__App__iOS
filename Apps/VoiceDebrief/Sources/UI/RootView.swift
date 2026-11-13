import SwiftUI

struct RootView: View {
    @State private var session = DebriefSession()

    var body: some View {
        TabView {
            DebriefView(session: session)
                .tabItem { Label("Debrief", systemImage: "waveform") }
            DiagnosticsView(session: session)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            StatusView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}
