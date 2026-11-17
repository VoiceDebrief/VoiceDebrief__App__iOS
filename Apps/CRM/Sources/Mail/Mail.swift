import Foundation

/// A message as the inbox shows it, read from Gmail's API (users.messages.get, format=full).
struct MailMessage: Identifiable, Hashable, Sendable {
    var id: String
    var threadID: String
    var from: String
    var fromAddress: String
    var to: String
    var subject: String
    var date: Date
    var snippet: String
    var body: String
    var unread: Bool
    var messageID: String?   // the RFC 5322 Message-ID, for replies
    var references: String?

    /// Reads one message from the API's JSON: headers, labels, and the text of the body (plain text, or HTML
    /// with its tags taken out when that is all there is).
    static func parse(_ json: [String: Any]) -> MailMessage? {
        guard let id = json["id"] as? String, let payload = json["payload"] as? [String: Any] else { return nil }
        let headers = Dictionary(((payload["headers"] as? [[String: Any]]) ?? []).compactMap { h -> (String, String)? in
            guard let n = h["name"] as? String, let v = h["value"] as? String else { return nil }
            return (n.lowercased(), v)
        }, uniquingKeysWith: { a, _ in a })
        let from = headers["from"] ?? ""
        let millis = Double((json["internalDate"] as? String) ?? "") ?? 0
        let labels = (json["labelIds"] as? [String]) ?? []
        return MailMessage(id: id, threadID: (json["threadId"] as? String) ?? id, from: displayName(from), fromAddress: address(from),
                           to: headers["to"] ?? "", subject: headers["subject"] ?? "(no subject)",
                           date: millis > 0 ? Date(timeIntervalSince1970: millis / 1000) : Date(),
                           snippet: ((json["snippet"] as? String) ?? "").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\""),
                           body: text(of: payload), unread: labels.contains("UNREAD"),
                           messageID: headers["message-id"], references: headers["references"])
    }

    /// `Ana Exemplo <ana@example.org>` → `ana@example.org`.
    static func address(_ header: String) -> String {
        if let open = header.lastIndex(of: "<"), let close = header.lastIndex(of: ">"), open < close {
            return String(header[header.index(after: open)..<close]).lowercased()
        }
        return header.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func displayName(_ header: String) -> String {
        guard let open = header.lastIndex(of: "<") else { return header }
        let name = header[..<open].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return name.isEmpty ? address(header) : name
    }

    static func text(of part: [String: Any]) -> String {
        let mime = (part["mimeType"] as? String) ?? ""
        if let parts = part["parts"] as? [[String: Any]] {
            if let plain = parts.lazy.map({ text(of: $0) }).first(where: { !$0.isEmpty && !$0.hasPrefix("<") }) { return plain }
            return parts.lazy.map { text(of: $0) }.first { !$0.isEmpty } ?? ""
        }
        guard let data = (part["body"] as? [String: Any])?["data"] as? String, let decoded = decode(data) else { return "" }
        return mime == "text/html" ? stripTags(decoded) : (mime.hasPrefix("text/") ? decoded : "")
    }

    static func decode(_ base64url: String) -> String? {
        var s = base64url.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func stripTags(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (a, b) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&#39;", "'"), ("&quot;", "\"")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// An email to send, made into the RFC 5322 text Gmail's send call takes.
struct OutgoingMail: Sendable {
    var from: String
    var to: [String]
    var subject: String
    var body: String
    var inReplyTo: String?
    var references: String?
    var threadID: String?

    /// Header values cannot carry a line break: that would let a value add headers of its own.
    static func clean(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.map { $0 == "\r" || $0 == "\n" ? " " : $0 }))
    }

    /// A subject outside ASCII, as an RFC 2047 encoded word.
    static func encodeSubject(_ s: String) -> String {
        let c = clean(s)
        return c.allSatisfy(\.isASCII) ? c : "=?UTF-8?B?" + Data(c.utf8).base64EncodedString() + "?="
    }

    var rfc5322: String {
        var lines = ["From: \(Self.clean(from))", "To: \(Self.clean(to.joined(separator: ", ")))",
                     "Subject: \(Self.encodeSubject(subject))", "MIME-Version: 1.0",
                     "Content-Type: text/plain; charset=UTF-8", "Content-Transfer-Encoding: base64"]
        if let inReplyTo { lines.append("In-Reply-To: \(Self.clean(inReplyTo))") }
        if let r = references ?? inReplyTo { lines.append("References: \(Self.clean(r))") }
        let encoded = Data(body.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        return lines.joined(separator: "\r\n") + "\r\n\r\n" + encoded + "\r\n"
    }

    /// What the send call takes: the message, base64url.
    var raw: String { GoogleAuth.base64URL(Data(rfc5322.utf8)) }

    /// A reply to a message: to its sender, "Re:" once, threaded.
    static func reply(to m: MailMessage, from me: String, body: String) -> OutgoingMail {
        let subject = m.subject.lowercased().hasPrefix("re:") ? m.subject : "Re: \(m.subject)"
        let refs = [m.references, m.messageID].compactMap { $0 }.joined(separator: " ")
        return OutgoingMail(from: me, to: [m.fromAddress], subject: subject, body: body,
                            inReplyTo: m.messageID, references: refs.isEmpty ? nil : refs, threadID: m.threadID)
    }
}

/// Gmail's REST API, with the person's token: the inbox, one message, the address, and sending.
struct GmailClient: Sendable {
    let token: @Sendable () async throws -> String
    static let base = "https://gmail.googleapis.com/gmail/v1/users/me"

    private func get(_ path: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: Self.base + path)!)
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw GoogleAuth.Problem.refused(((json["error"] as? [String: Any])?["message"] as? String) ?? "status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return json
    }

    func address() async throws -> String {
        try await get("/profile")["emailAddress"] as? String ?? ""
    }

    /// The latest messages in a label (the inbox by default), newest first.
    func list(label: String = "INBOX", max: Int = 30, query: String? = nil) async throws -> [MailMessage] {
        var path = "/messages?maxResults=\(max)&labelIds=\(label)"
        if let query, !query.isEmpty { path += "&q=" + (query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "") }
        let ids = ((try await get(path))["messages"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        var out: [MailMessage] = []
        try await withThrowingTaskGroup(of: MailMessage?.self) { group in
            for id in ids { group.addTask { MailMessage.parse(try await get("/messages/\(id)?format=full")) } }
            for try await m in group { if let m { out.append(m) } }
        }
        return out.sorted { $0.date > $1.date }
    }

    /// Sends, as the person, only when they pressed Send and confirmed this very message: the consent can only be
    /// made by the confirmation in ComposeView (InboxView.swift), and it names the message it was given for.
    /// No lane, agent or vault app path can make one; `MailTests` holds the sources to that.
    func send(_ mail: OutgoingMail, consent: PersonConfirmedSend) async throws {
        guard consent.raw == mail.raw else { throw GoogleAuth.Problem.refused("this is not the message you confirmed") }
        var request = URLRequest(url: URL(string: Self.base + "/messages/send")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["raw": mail.raw]
        if let thread = mail.threadID { body["threadId"] = thread }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw GoogleAuth.Problem.refused(((json["error"] as? [String: Any])?["message"] as? String) ?? "not sent")
        }
    }
}
