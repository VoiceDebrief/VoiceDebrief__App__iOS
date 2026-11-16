import SwiftUI

/// The workflows the CRM is made of, each with its cells and whether it is built.
struct WorkflowsView: View {
    var body: some View {
        List {
            Section {
                Text("Cells make workflows, workflows make plays, and plays make the CRM. A cell is code, a call to Apple's models on this device, a call to a cloud model behind a lane, an agent, or a decision only you take.")
                    .font(.footnote)
            }
            ForEach(CRMWorkflow.all) { workflow in
                Section {
                    LabeledContent("Trigger", value: workflow.trigger)
                    ForEach(workflow.cells, id: \.self) { cell in
                        HStack(alignment: .firstTextBaseline) {
                            Text(cell.kind.altitude).font(.caption.monospaced()).frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading) {
                                Text(cell.job)
                                Text("\(cell.kind.name), \(cell.kind.runsIn)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    LabeledContent("Writes", value: workflow.writes)
                    LabeledContent("Waits for you", value: workflow.waitsFor)
                } header: {
                    HStack {
                        Text("\(workflow.id) · \(workflow.title)")
                        Spacer()
                        Text(workflow.status.rawValue).foregroundStyle(workflow.isBuilt ? Color.green : .secondary)
                    }
                }
            }
        }
        .navigationTitle("Workflows")
    }
}
