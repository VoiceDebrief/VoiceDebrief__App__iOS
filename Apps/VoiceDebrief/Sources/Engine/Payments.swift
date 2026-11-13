import Foundation
import StoreKit

/// Something that can be bought: an amount of credit.
struct CreditPack: Identifiable, Equatable, Sendable {
    /// The product id, as it is (or will be) in App Store Connect.
    let id: String
    /// Micro-credits added to the balance.
    let credit: Int
    /// What the buyer pays, as the provider words it.
    let priceText: String
}

/// Proof, as far as the provider can give it, that a top-up was paid for.
struct PaymentReceipt: Equatable, Sendable {
    /// Credited once per reference.
    let ref: String
    let credit: Int
    /// "simulated", or "appstore:" and the App Store's environment ("sandbox", "production", "xcode").
    let source: String
}

enum PaymentOutcome: Equatable, Sendable {
    case paid(PaymentReceipt)
    case cancelled
    /// Waiting for someone else's approval (Ask to Buy, or the bank). The credit arrives later.
    case pending
}

enum PaymentError: LocalizedError {
    case notOnSale
    case notVerified

    var errorDescription: String? {
        switch self {
        case .notOnSale: return "The App Store does not offer this top-up."
        case .notVerified: return "The App Store's receipt for this payment could not be verified, so no credit was added."
        }
    }
}

/// The way a top-up is paid for. One type per way: the ledger and the screens do not change.
@MainActor
protocol PaymentProvider {
    /// True if no money moves. The top-up screen says so in words.
    var isSimulated: Bool { get }
    /// What can be bought now. Empty means there is nothing to offer, and the screen offers nothing.
    func packs() async -> [CreditPack]
    /// Takes the payment. `record` is called with the receipt before the payment is marked as
    /// delivered, so that a payment taken is never a credit lost.
    func buy(_ pack: CreditPack, record: (PaymentReceipt) -> Void) async throws -> PaymentOutcome
    /// Payments that were taken and never recorded (the app closed, or an approval came later).
    func recover(record: (PaymentReceipt) -> Void) async
}

/// What is on sale, and the switch between the simulated payment and the App Store.
enum Payments {
    /// OFF until the products below exist in App Store Connect and the Paid Applications Agreement is
    /// signed. While it is off no screen offers an App Store purchase. See website/credit/index.md.
    static let appStoreIsOn = false

    /// The packs, and what each adds. PLACEHOLDER: one pack of five pounds, as newsroom has; the
    /// owner sets the amounts and creates products with exactly these ids.
    static let catalogue: [(id: String, credit: Int)] = [
        (id: "ai.voicedebrief.app.credit.500", credit: 5 * Credit.perPound),
    ]

    @MainActor static var provider: any PaymentProvider {
        if appStoreIsOn { return AppStorePayments() }
        return SimulatedPayments()
    }
}

/// The test build's payment: every step but the payment. No money is taken, and the ledger says so.
struct SimulatedPayments: PaymentProvider {
    let isSimulated = true

    func packs() async -> [CreditPack] {
        Payments.catalogue.map { CreditPack(id: $0.id, credit: $0.credit, priceText: Credit.money($0.credit)) }
    }

    func buy(_ pack: CreditPack, record: (PaymentReceipt) -> Void) async throws -> PaymentOutcome {
        let receipt = PaymentReceipt(ref: "simulated-\(UUID().uuidString)", credit: pack.credit, source: "simulated")
        record(receipt)
        return .paid(receipt)
    }

    func recover(record: (PaymentReceipt) -> Void) async {}
}

/// Consumable in-app purchases with StoreKit 2. WRITTEN, NEVER RUN: there are no products yet, so
/// `Payments.appStoreIsOn` is false and nothing reaches this type. A build from TestFlight uses the
/// App Store's sandbox, which takes no money.
struct AppStorePayments: PaymentProvider {
    let isSimulated = false

    func packs() async -> [CreditPack] {
        guard let products = try? await Product.products(for: Payments.catalogue.map { $0.id }) else { return [] }
        return Payments.catalogue.compactMap { item in
            guard let product = products.first(where: { $0.id == item.id }), product.type == .consumable else { return nil }
            return CreditPack(id: item.id, credit: item.credit, priceText: product.displayPrice)
        }
    }

    func buy(_ pack: CreditPack, record: (PaymentReceipt) -> Void) async throws -> PaymentOutcome {
        guard let product = try await Product.products(for: [pack.id]).first else { throw PaymentError.notOnSale }
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result else { throw PaymentError.notVerified }
            let receipt = Self.receipt(for: transaction, credit: pack.credit)
            record(receipt)
            await transaction.finish()
            return .paid(receipt)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func recover(record: (PaymentReceipt) -> Void) async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result,
                  let item = Payments.catalogue.first(where: { $0.id == transaction.productID }) else { continue }
            record(Self.receipt(for: transaction, credit: item.credit))
            await transaction.finish()
        }
    }

    private static func receipt(for transaction: Transaction, credit: Int) -> PaymentReceipt {
        PaymentReceipt(ref: "appstore-\(transaction.id)", credit: credit,
                       source: "appstore:" + transaction.environment.rawValue.lowercased())
    }
}
