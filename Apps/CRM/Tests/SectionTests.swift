import Testing
@testable import CRM

/// Reality discipline for the app's own screens: a section claims to be built only when it is.
@MainActor
struct SectionTests {
    @Test func everySidebarSectionIsUnique() {
        #expect(Set(CRMSection.sidebar).count == CRMSection.sidebar.count)
        #expect(!CRMSection.sidebar.contains(.about))
    }

    @Test func everySectionHasATitleAnIconAndAPurpose() {
        for section in CRMSection.allCases {
            #expect(!section.title.isEmpty)
            #expect(!section.systemImage.isEmpty)
            #expect(section.purpose.hasSuffix("."))
        }
    }

    /// People and organisations (step 2) and import (step 3) are built. When a step lands, its section moves here.
    @Test func onlyWhatIsBuiltSaysBuilt() {
        let built = CRMSection.allCases.filter(\.isBuilt)
        #expect(built == [.people, .organisations, .importing, .workflows, .about])
    }

    @Test func unbuiltSectionsNameTheirStep() throws {
        for section in CRMSection.allCases where !section.isBuilt {
            let step = try #require(section.step)
            #expect((4...7).contains(step))
        }
    }

    @Test func draftsNeverClaimToSend() {
        #expect(CRMSection.drafts.purpose.contains("send them yourself"))
        #expect(CRMSection.drafts.purpose.contains("never sends"))
    }

    @Test func theBundleIsTheOwnersChoice() {
        // In the test host the bundle is the app's own.
        #expect(AppInfo.bundleID == "ai.sgit.crm.app")
    }
}
