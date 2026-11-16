import Testing
@testable import CRM

/// The workflows the app lists must match website/crm/workflows/ and the reality file.
struct WorkflowTests {
    @Test func workflowsInOrder() {
        #expect(CRMWorkflow.all.map(\.id) == (1...12).map { "W\($0)" })
    }

    @Test func onlyImportAndTheListAreBuiltAndHaveAPlace() {
        let built = CRMWorkflow.all.filter(\.isBuilt)
        #expect(built.map(\.id) == ["W1", "W3", "W5", "W11", "W12"])
        for w in built { #expect(w.section?.isBuilt == true) }
    }

    @Test func everyWorkflowThatChangesRecordsWaitsForAPerson() {
        for w in CRMWorkflow.all where w.cells.count > 1 {
            #expect(w.cells.contains { $0.kind == .person }, "\(w.id) has no person cell")
        }
    }

    @Test func noCloudOrAgentCellRunsInTheApp() {
        for w in CRMWorkflow.all {
            for cell in w.cells where cell.kind == .cloud || cell.kind == .agent {
                #expect(!cell.kind.runsIn.hasPrefix("in the app"))
            }
        }
    }
}
