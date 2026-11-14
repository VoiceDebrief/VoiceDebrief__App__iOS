import Foundation

/// Answers recorded from dev.send.sgraph.ai on 14 November 2026, by a script in the session that wrote this
/// package, against a throwaway vault made for the purpose and destroyed afterwards. Two messages were written
/// (the payloads `aGVsbG8gb25l` and `aGVsbG8gdHdv`, "hello one" and "hello two"), listed, one fetched and marked
/// processed, and the list asked again. Redacted: the lane id the server returns as `inbox` (it is the append
/// token) and the vault id. Everything else is byte for byte what the server said, re-serialised compactly.
///
/// What the recording shows and the tests rely on: the server stores a payload as it was written and returns it
/// unchanged as `content`, so a test may put its own sealed payload into a recorded answer's `content`.
/// A wrong append token, a missing or wrong enumeration key, and a vault that does not exist all answer 404
/// with an HTML page.
enum RecordedLane {
    static let configured = #"{"vault_id":"recordedvault","status":"configured"}"#
    static let listEmpty = #"{"status":"ok","entries":[],"truncated":false}"#
    static let writeOK = #"{"ok":true}"#
    static let listTwo = #"{"status":"ok","entries":[{"inbox":"recorded-append-token-redacted","file_id":"1794649267280_0c456df3471d05f8941f7b0b.enc","received":1794649267280},{"inbox":"recorded-append-token-redacted","file_id":"1794649268460_5a680ddf665ce05f8a586c76.enc","received":1794649268460}],"truncated":false}"#
    static let listTwoWithContent = #"{"status":"ok","entries":[{"inbox":"recorded-append-token-redacted","file_id":"1794649267280_0c456df3471d05f8941f7b0b.enc","received":1794649267280,"size":9,"content":"aGVsbG8gb25l"},{"inbox":"recorded-append-token-redacted","file_id":"1794649268460_5a680ddf665ce05f8a586c76.enc","received":1794649268460,"size":9,"content":"aGVsbG8gdHdv"}],"truncated":false}"#
    static let fetchOne = #"{"status":"ok","files":[{"file_id":"1794649267280_0c456df3471d05f8941f7b0b.enc","size":9,"content":"aGVsbG8gb25l"}],"missing":[]}"#
    static let markOne = #"{"status":"ok","moved":["1794649267280_0c456df3471d05f8941f7b0b.enc"],"missing":[]}"#
    static let listAfterMark = #"{"status":"ok","entries":[{"inbox":"recorded-append-token-redacted","file_id":"1794649268460_5a680ddf665ce05f8a586c76.enc","received":1794649268460}],"truncated":false}"#
    /// The first line of the 404 page the server answered for a bad token, a bad key and an unknown vault.
    static let notFoundPage = "<!DOCTYPE html>\n<html lang=\"en-GB\">"
    static let fileOne = "1794649267280_0c456df3471d05f8941f7b0b.enc"
    static let fileTwo = "1794649268460_5a680ddf665ce05f8a586c76.enc"
    static let lane = "recorded-append-token-redacted"
}
