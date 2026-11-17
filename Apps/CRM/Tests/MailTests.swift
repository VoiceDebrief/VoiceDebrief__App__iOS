import Foundation
import Testing
@testable import CRM

/// The parts of the Gmail inbox that need no server: PKCE, the redirect, the mail we write, and reading headers.
/// No Gmail responses are invented here; the API itself is tried on a device.
struct MailTests {
    @Test func pkceMatchesTheRFC7636Example() {
        // RFC 7636, appendix B.
        #expect(GoogleAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func aVerifierIsLongEnoughAndURLSafe() {
        let v = GoogleAuth.verifier()
        #expect(v.count >= 43 && v.count <= 128)
        #expect(v.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(GoogleAuth.verifier() != v)
    }

    @Test func theRedirectIsTheClientIDReversed() {
        let id = "123456789012-abcdefghijk.apps.googleusercontent.com"
        #expect(GoogleAuth.redirectScheme(for: id) == "com.googleusercontent.apps.123456789012-abcdefghijk")
        #expect(GoogleAuth.redirectURI(for: id) == "com.googleusercontent.apps.123456789012-abcdefghijk:/oauth2redirect")
    }

    @Test func theSignInPageAsksForReadAndSendOnly() throws {
        let url = GoogleAuth.authorizeURL(clientID: "1-a.apps.googleusercontent.com", challenge: "c", state: "s")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let value = { (name: String) in items.first { $0.name == name }?.value }
        #expect(url.host() == "accounts.google.com")
        #expect(value("scope") == "https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.send")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("response_type") == "code")
        #expect(value("client_secret") == nil)
    }

    @MainActor @Test func theClientIDIsAcceptedEitherWayRound() {
        let auth = GoogleAuth(store: MemoryStore(), defaults: UserDefaults(suiteName: "crm-mail-tests")!)
        auth.setClient(" com.googleusercontent.apps.1-a \n")
        #expect(auth.clientID == "1-a.apps.googleusercontent.com")
        #expect(!auth.signedIn)
        auth.setClient("")
        #expect(!auth.hasClient)
    }

    @Test func aHeaderValueCannotAddHeaders() {
        let mail = OutgoingMail(from: "owner@example.org", to: ["ana@example.org"], subject: "Hello\r\nBcc: someone@example.net", body: "Hi")
        let head = mail.rfc5322.components(separatedBy: "\r\n\r\n")[0]
        #expect(!head.contains("\r\nBcc:"))
        #expect(head.contains("Subject: Hello  Bcc: someone@example.net"))
    }

    @Test func theMessageIsRFC5322WithABase64Body() throws {
        let mail = OutgoingMail(from: "owner@example.org", to: ["ana@example.org", "tom@example.com"], subject: "Olá from the summit", body: "Good to meet you.\nSpeak soon.")
        let parts = mail.rfc5322.components(separatedBy: "\r\n\r\n")
        #expect(parts[0].hasPrefix("From: owner@example.org\r\nTo: ana@example.org, tom@example.com\r\n"))
        #expect(parts[0].contains("Subject: =?UTF-8?B?\(Data("Olá from the summit".utf8).base64EncodedString())?="))
        #expect(parts[0].contains("Content-Transfer-Encoding: base64"))
        let body = try #require(Data(base64Encoded: parts[1].replacingOccurrences(of: "\r\n", with: "")))
        #expect(String(decoding: body, as: UTF8.self) == "Good to meet you.\nSpeak soon.")
        #expect(!mail.raw.contains("+") && !mail.raw.contains("/") && !mail.raw.contains("="))
        #expect(MailMessage.decode(mail.raw) == mail.rfc5322)
    }

    @Test func aReplyGoesToTheSenderOnceThreaded() {
        let m = MailMessage(id: "m1", threadID: "t1", from: "Ana Exemplo", fromAddress: "ana@example.org", to: "owner@example.org",
                            subject: "Good to meet you", date: Date(timeIntervalSince1970: 0), snippet: "", body: "", unread: true,
                            messageID: "<m1@example.org>", references: "<m0@example.org>")
        let r = OutgoingMail.reply(to: m, from: "owner@example.org", body: "Likewise")
        #expect(r.to == ["ana@example.org"])
        #expect(r.subject == "Re: Good to meet you")
        #expect(r.threadID == "t1")
        #expect(r.references == "<m0@example.org> <m1@example.org>")
        #expect(r.rfc5322.contains("In-Reply-To: <m1@example.org>"))
        var again = m
        again.subject = r.subject
        #expect(OutgoingMail.reply(to: again, from: "owner@example.org", body: "").subject == "Re: Good to meet you")
    }

    @Test func addressesAndNamesFromAHeader() {
        #expect(MailMessage.address("Ana Exemplo <Ana@Example.org>") == "ana@example.org")
        #expect(MailMessage.address(" tom@example.com ") == "tom@example.com")
        #expect(MailMessage.displayName("\"Ana Exemplo\" <ana@example.org>") == "Ana Exemplo")
        #expect(MailMessage.displayName("<ana@example.org>") == "ana@example.org")
    }

    @Test func htmlBecomesText() {
        #expect(MailMessage.stripTags("<style>p{}</style><p>Hello&nbsp;Ana</p><p>A &amp; B<br>next</p>") == "Hello Ana\n\nA & B\nnext")
    }
}
