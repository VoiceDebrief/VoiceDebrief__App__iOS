import SwiftUI

/// The balance, always in sight: a small capsule for a navigation bar. It changes as things are
/// charged, and opens the credit screen. Below zero it turns a warmer colour and nothing else
/// happens: no banner, nothing blocked (after newsroom.sgit.ai's meter).
struct CreditCounter: View {
    private let ledger = CreditLedger.shared
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            // Marked as test credit where it is shown: three users read a bare amount as paying per memo
            // (review rounds 1 and 2, issue 032). Recording never stops for credit.
            Text("Test credit " + Credit.money(ledger.balance))
                .font(.caption.weight(.semibold).monospacedDigit())
                .fixedSize()
                .foregroundStyle(ledger.isBelowZero ? Color.orange : Color.primary)
                .contentTransition(.numericText(value: Double(ledger.balance)))
                .animation(.snappy, value: ledger.balance)
        }
        .accessibilityLabel("Test credit: \(Credit.money(ledger.balance)). No money is taken and recording never stops.")
        .accessibilityHint(ledger.isBelowZero ? "Below zero. Nothing is blocked. Opens your credit." : "Opens your credit.")
        .sheet(isPresented: $showing) {
            NavigationStack {
                CreditView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showing = false }
                        }
                    }
            }
        }
    }
}

/// The credit screen: the balance, top-up, every entry newest first, and the prices.
struct CreditView: View {
    private let ledger = CreditLedger.shared
    private let provider = Payments.provider
    @State private var packs: [CreditPack] = []
    @State private var confirming: CreditPack?
    @State private var declining: CreditEntry?
    @State private var paying = false
    @State private var said: String?

    var body: some View {
        List {
            balance
            topUp
            Section {
                NavigationLink("Takings by feature") { TakingsView() }
            } footer: {
                Text("What each feature has been used for and charged, on this device.")
            }
            entries
            prices
            Section {
                Link("How credit works, and what is not built", destination: AppInfo.site.appending(path: "credit/index.html"))
            } footer: {
                Text("The ledger is kept on this device only, and nothing checks it. Deleting the app starts again at \(Credit.money(Credit.startingCredit)).")
            }
        }
        .readableWidth()
        .navigationTitle("Credit")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await provider.recover { ledger.topUp($0) }
            packs = await provider.packs()
        }
        .confirmationDialog(confirming.map { "Add \(Credit.money($0.credit)) of credit" } ?? "", isPresented: confirmingBinding,
                            titleVisibility: .visible, presenting: confirming) { pack in
            Button(provider.isSimulated ? "Confirm (simulated)" : "Pay \(pack.priceText)") {
                Task { await buy(pack) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pack in
            Text(provider.isSimulated
                 ? "This is a test build. The payment is simulated: no money is taken and no card is asked for. \(Credit.money(pack.credit)) is added to the balance on this device."
                 : "\(pack.priceText), paid through the App Store. One payment: nothing renews.")
        }
        .confirmationDialog("Don't charge me for this", isPresented: decliningBinding, titleVisibility: .visible, presenting: declining) { entry in
            ForEach(CreditBook.declineReasons, id: \.self) { reason in
                Button(reason) { ledger.decline(entry, reason: reason) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("\(entry.text): \(Credit.money(-entry.amount)) is given back, and the reason is kept in the ledger.")
        }
    }

    private var confirmingBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var decliningBinding: Binding<Bool> {
        Binding(get: { declining != nil }, set: { if !$0 { declining = nil } })
    }

    // MARK: Sections

    private var balance: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(Credit.money(ledger.balance))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(ledger.isBelowZero ? Color.orange : Color.primary)
                    .contentTransition(.numericText(value: Double(ledger.balance)))
                    .animation(.snappy, value: ledger.balance)
                if ledger.isBelowZero {
                    Text("You have used \(Credit.money(-ledger.balance)) more than your credit. Nothing is blocked, and nothing will be. Top up when it feels fair.")
                        .font(.callout)
                } else {
                    Text("Test credit: you started with \(Credit.money(Credit.startingCredit)) and it counts down as the app is used. No money is taken in this test build. It may go below zero, and nothing is blocked when it does: recording never stops for credit.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            LabeledContent("Used", value: Credit.money(ledger.book.spent))
            LabeledContent("Topped up", value: Credit.money(ledger.book.toppedUp))
            if let problem = ledger.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
    }

    private var topUp: some View {
        Section {
            if provider.isSimulated {
                Label("Test build: payments are simulated. No money is taken.", systemImage: "testtube.2")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            ForEach(packs) { pack in
                Button {
                    confirming = pack
                } label: {
                    LabeledContent {
                        Text(provider.isSimulated ? "simulated" : pack.priceText)
                    } label: {
                        Label("Add \(Credit.money(pack.credit)) of credit", systemImage: "plus.circle")
                    }
                }
                .disabled(paying)
            }
            if packs.isEmpty, !provider.isSimulated {
                Text("There is nothing to buy at the moment.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let said {
                Text(said).font(.callout)
            }
        } header: {
            Text("Top up")
        } footer: {
            Text(provider.isSimulated
                 ? "When the app is on the App Store a top-up will be an in-app purchase. Until then this is every step but the payment."
                 : "One payment through the App Store. Nothing renews, and credit does not expire.")
        }
    }

    private var entries: some View {
        Section {
            ForEach(ledger.newestFirst) { entry in
                EntryRow(entry: entry, declined: ledger.book.isDeclined(entry))
                    .swipeActions(edge: .trailing) {
                        if entry.kind == .charge, !ledger.book.isDeclined(entry) {
                            Button("Don't charge me") { declining = entry }
                                .tint(.orange)
                        }
                    }
            }
        } header: {
            Text("Ledger")
        } footer: {
            Text("Every charge and top-up, newest first. Swipe a charge to decline it, with a reason: it is given back.")
        }
    }

    private var prices: some View {
        Section {
            ForEach(PriceList.all) { price in
                LabeledContent(price.title, value: price.words)
            }
        } header: {
            Text("Prices")
        } footer: {
            Text((PriceList.arePlaceholders ? "Placeholder prices: these have not been set yet and will change. " : "")
                 + "Something that fails costs nothing. Running a note again is charged again. Recording is never charged and never stopped.")
        }
    }

    private func buy(_ pack: CreditPack) async {
        paying = true
        defer { paying = false }
        do {
            switch try await provider.buy(pack, record: { ledger.topUp($0) }) {
            case .paid(let receipt):
                said = receipt.source == "simulated"
                    ? "\(Credit.money(receipt.credit)) added. Simulated: nothing was charged."
                    : "\(Credit.money(receipt.credit)) added."
            case .pending:
                said = "The payment is waiting for approval. The credit is added when it comes through."
            case .cancelled:
                said = nil
            }
        } catch {
            said = error.localizedDescription
        }
    }
}

private struct EntryRow: View {
    let entry: CreditEntry
    let declined: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .font(.callout)
                    .strikethrough(declined)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text((entry.amount > 0 ? "+" : "") + Credit.money(entry.amount))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(entry.amount > 0 ? Color.green : Color.primary)
                Text(Credit.money(entry.balance))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(entry.balance < 0 ? Color.orange : Color.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [entry.at.formatted(date: .abbreviated, time: .shortened)]
        if let reason = entry.reason { parts.append(reason) }
        if declined { parts.append("declined") }
        return parts.joined(separator: " · ")
    }
}

/// The ledger by feature: the revenue side of a profit and loss, for this device only.
struct TakingsView: View {
    private let ledger = CreditLedger.shared
    @State private var days = 0

    private var lines: [FeatureLine] {
        ledger.book.byFeature(since: days == 0 ? nil : Date().addingTimeInterval(-Double(days) * 86_400))
    }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $days) {
                    Text("All").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
            }
            Section {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        LabeledContent(PriceList.title(ofFeature: line.feature), value: Credit.money(line.net))
                        Text(detail(line))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if lines.isEmpty {
                    Text("Nothing has been charged in this period.").foregroundStyle(.secondary)
                } else {
                    LabeledContent("Total", value: Credit.money(lines.reduce(0) { $0 + $1.net }))
                        .fontWeight(.semibold)
                }
            } footer: {
                Text("Takings only, and only this device's. What each feature costs to provide, and the same figures across everybody who uses the app, are not built. Top-ups in this build are simulated, so none of this is money.")
            }
        }
        .readableWidth()
        .navigationTitle("Takings by feature")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ line: FeatureLine) -> String {
        var text = "\(line.uses) charged, \(Credit.money(line.charged))"
        if line.declined > 0 { text += " · \(line.declined) declined, \(Credit.money(line.givenBack)) given back" }
        return text
    }
}
