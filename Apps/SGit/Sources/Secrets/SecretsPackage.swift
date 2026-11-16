// The secret format (SecretEntry, SecretKindOfEntry) and the password maker now live in the SGitSecrets
// package, shared with SGit Secrets. Re-exported here so that every file in this app, and the app's tests
// through `@testable import SGit`, see them exactly as before the move.
@_exported import SGitSecrets
