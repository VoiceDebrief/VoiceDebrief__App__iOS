import SwiftUI

/// A sidebar on an iPad, a list that pushes on an iPhone: NavigationSplitView collapses on its own.
struct RootView: View {
    @State private var selection: CRMSection? = .followUps

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(CRMSection.sidebar) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                    }
                }
                Section {
                    NavigationLink(value: CRMSection.about) {
                        Label(CRMSection.about.title, systemImage: CRMSection.about.systemImage)
                    }
                }
            }
            .navigationTitle("SGit CRM")
        } detail: {
            NavigationStack {
                SectionScreen(section: selection ?? .followUps)
            }
        }
    }
}

/// One section's screen. A section not built yet says so, and which step of the brief builds it.
struct SectionScreen: View {
    let section: CRMSection

    var body: some View {
        Group {
            if section == .about {
                AboutView()
            } else {
                ContentUnavailableView {
                    Label(section.title, systemImage: section.systemImage)
                } description: {
                    Text(section.purpose)
                    if let step = section.step {
                        Text("Not built yet: step \(step) of the plan.")
                            .font(.footnote)
                    }
                }
            }
        }
        .navigationTitle(section.title)
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: AppInfo.versionLine)
                LabeledContent("Bundle", value: AppInfo.bundleID)
            }
            Section("What it is") {
                Text("A CRM of our own, on sgit vaults the user owns. First used to follow up the contacts and actions from Web Summit 2026.")
                Text("Agents propose records and drafts; a person reviews them and sends every message themselves.")
            }
            Section("What this build does") {
                ForEach(CRMSection.sidebar) { section in
                    LabeledContent(section.title, value: section.isBuilt ? "Built" : "Not built yet")
                }
            }
        }
    }
}

#Preview {
    RootView()
}
