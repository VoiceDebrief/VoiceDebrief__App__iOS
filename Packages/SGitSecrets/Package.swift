// swift-tools-version: 6.0
// SGitSecrets: what a secret is, for SGit Vaults and SGit Secrets. One secret is one encrypted JSON file in a
// vault's secrets/ folder (format sgit.ai/secret/v1), its kinds and their fields, and the password maker.
// Moved here from SGit Vaults (Apps/SGit/Sources/Secrets/SecretEntry.swift) without changing behaviour.
// Apple SDK only (Foundation, Security).
import PackageDescription

let package = Package(
    name: "SGitSecrets",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SGitSecrets", targets: ["SGitSecrets"]),
    ],
    targets: [
        .target(name: "SGitSecrets"),
        .testTarget(name: "SGitSecretsTests", dependencies: ["SGitSecrets"], path: "Tests/SGitSecretsTests"),
    ],
    // The apps build in Swift 5 mode with complete concurrency checking; the package does the same.
    swiftLanguageModes: [.v5]
)
