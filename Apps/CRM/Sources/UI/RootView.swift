import SwiftUI

/// A sidebar on an iPad, a list that pushes on an iPhone: NavigationSplitView collapses on its own.
struct RootView: View {
    let crm: CRMVault
    var problem: String?
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
            .safeAreaInset(edge: .bottom) {
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.footnote).padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.15))
                }
            }
        } detail: {
            NavigationStack {
                SectionScreen(section: selection ?? .followUps, crm: crm)
            }
        }
    }
}

/// One section's screen. A section not built yet says so, and which step of the brief builds it.
struct SectionScreen: View {
    let section: CRMSection
    let crm: CRMVault

    var body: some View {
        Group {
            switch section {
            case .about:
                AboutView(crm: crm)
            case .people:
                PeopleList(crm: crm)
            case .organisations:
                OrganisationsList(crm: crm)
            case .importing:
                ImportView(crm: crm)
            default:
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
    let crm: CRMVault

    var body: some View {
        List {
            Section {
                LabeledContent("Version", value: AppInfo.versionLine)
                LabeledContent("Bundle", value: AppInfo.bundleID)
            }
            Section("Your CRM vault") {
                LabeledContent("Kept", value: "On this device")
                if let id = crm.vaultID { LabeledContent("Vault", value: id).font(.footnote.monospaced()) }
                LabeledContent("People", value: "\(crm.people.count)")
                LabeledContent("Organisations", value: "\(crm.organisations.count)")
                LabeledContent("Commits", value: "\(crm.commits)")
                if let key = crm.signerFingerprint { LabeledContent("Signing key", value: key).font(.footnote.monospaced()) }
                if !crm.unreadable.isEmpty { LabeledContent("Files that are not valid records", value: "\(crm.unreadable.count)") }
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
    RootView(crm: CRMVault(store: MemoryStore(), root: FileManager.default.temporaryDirectory.appending(path: "crm-preview")))
}
