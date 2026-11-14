// swift-tools-version: 6.0
// SGitPeople: the layer under VoiceDebrief and SGit Vaults. A person's key bundle (PKIKit), their contact
// card, contacts, sealed and signed messages, an inbox on an append lane, and a secrets store.
// Apple SDK only (CryptoKit, CommonCrypto, Security, LocalAuthentication), plus the local SGitVault package
// to create the vault an inbox lives on.
import PackageDescription

let package = Package(
    name: "SGitPeople",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SGitPeople", targets: ["SGitPeople"]),
    ],
    dependencies: [
        .package(path: "../SGitVault"),
    ],
    targets: [
        .target(
            name: "SGitPeople",
            dependencies: [.product(name: "SGitVault", package: "SGitVault")]
        ),
        .testTarget(
            name: "SGitPeopleTests",
            dependencies: ["SGitPeople", .product(name: "SGitVault", package: "SGitVault")],
            path: "Tests/SGitPeopleTests"
        ),
    ],
    // The apps build in Swift 5 mode with complete concurrency checking; the package does the same.
    swiftLanguageModes: [.v5]
)
