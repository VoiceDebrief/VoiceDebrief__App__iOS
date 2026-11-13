import SwiftUI

struct RootView: View {
    @State private var session = DebriefSession()
    @State private var book = VaultBook()

    var body: some View {
        TabView {
            DebriefView(session: session, book: book)
                .tabItem { Label("Debrief", systemImage: "waveform") }
            VaultsView(book: book)
                .tabItem { Label("Vaults", systemImage: "lock.shield") }
            DiagnosticsView(session: session)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            StatusView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}
