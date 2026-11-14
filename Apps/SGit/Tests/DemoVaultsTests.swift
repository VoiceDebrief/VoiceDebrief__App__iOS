import Foundation
import Testing
@testable import SGit

@Suite("The vaults published by sgit.ai, in the gallery")
struct DemoVaultsTests {
    private let index = """
    | # | Vault | What it is | Category | Files | Size | Published |
    |---|---|---|---|---|---|---|
    | 54 | [Synthetic users · newsroom.sgit.ai](newsroom-synthetic-users/index.md)`bg1opz3c` | Five invented readers | Analysis | 83 | 11991 KB | 2026-10-10 |
    | 46 | [Hope or enforcement](hope-or-enforcement/index.md)`wz9dw0m5` | Three designs | one model with rules | Reference | 12 | 300 KB | 2026-10-01 |
    Not a row | at all
    """

    @Test func theRowsAreReadEvenWithABarInTheSummary() {
        let rows = DemoCatalog.rows(fromIndex: index)
        #expect(rows.map(\\.number) == [54, 46])
        #expect(rows[0].vault == "bg1opz3c")
        #expect(rows[0].category == "Analysis")
        #expect(rows[0].page == "https://sgit.ai/demos/vaults/newsroom-synthetic-users/index.html")
        #expect(rows[1].summary == "Three designs | one model with rules")
        #expect(rows[1].files == 12)
        #expect(rows.allSatisfy { $0.readKey == nil })
    }

    @Test func onlyAPublicReadKeyForThatVaultIsTaken() {
        let page = "Read key: `sgit_public_read_\\(String(repeating: "ab", count: 32)):bg1opz3c` and another `sgit_public_read_\\(String(repeating: "cd", count: 32)):other123`"
        #expect(DemoCatalog.readKey(inPage: page, vault: "bg1opz3c")?.hasSuffix(":bg1opz3c") == true)
        #expect(DemoCatalog.readKey(inPage: page, vault: "missing1") == nil)
        #expect(DemoCatalog.readKey(inPage: "sgit_private_vault_x:bg1opz3c", vault: "bg1opz3c") == nil)
    }

    @Test func theCopyInTheAppHoldsOnlyPublicReadKeys() throws {
        let catalog = try #require(DemoCatalog.bundled())
        #expect(catalog.vaults.count >= 50)
        #expect(catalog.vaults.allSatisfy { ($0.readKey ?? "").hasPrefix("sgit_public_read_") })
        #expect(catalog.vaults.allSatisfy { SavedVault(id: $0.vault, name: $0.name, keyText: $0.readKey ?? "", addedAt: Date(), createdHere: false).canWrite == false })
    }

    @Test func liveRowsKeepTheBundledKeysAndGroupByCategory() {
        let bundled = DemoCatalog(format: "", source: "", fetched: "", vaults: [
            DemoVault(number: 54, name: "A", slug: "a", vault: "bg1opz3c", summary: "", category: "Analysis", files: 1,
                      size: "1 KB", published: "2026-10-10", page: "", readKey: "sgit_public_read_key:bg1opz3c")])
        let merged = bundled.merged(withLive: DemoCatalog.rows(fromIndex: index))
        #expect(merged.count == 2)
        #expect(merged.first { $0.vault == "bg1opz3c" }?.readKey == "sgit_public_read_key:bg1opz3c")
        #expect(merged.first { $0.vault == "wz9dw0m5" }?.readKey == nil)
        #expect(DemoCatalog.grouped(merged, search: "").map(\\.category) == ["Analysis", "Reference"])
        #expect(DemoCatalog.grouped(merged, search: "rules").map(\\.category) == ["Reference"])
        #expect(bundled.merged(withLive: []) == bundled.vaults)
    }
}
