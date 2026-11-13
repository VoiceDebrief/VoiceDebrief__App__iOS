// swift-tools-version: 6.0
// SGitVault: a native reader (and, later, writer) for sgit vaults.
// Apple SDK only: CryptoKit, CommonCrypto, Compression (through Foundation), Observation.
import PackageDescription

let package = Package(
    name: "SGitVault",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SGitVault", targets: ["SGitVault"]),
    ],
    targets: [
        .target(name: "SGitVault"),
        .testTarget(
            name: "SGitVaultTests",
            dependencies: ["SGitVault"],
            path: "Tests/SGitVaultTests"
        ),
    ]
)
