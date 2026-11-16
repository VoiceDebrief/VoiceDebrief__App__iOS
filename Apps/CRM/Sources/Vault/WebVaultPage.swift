import Observation
import SwiftUI
import UIKit
import WebKit

// Copied from Apps/SGit/Sources/UI/WebVaultView.swift (16 November 2026): the web Vault's embed protocol,
// version 1. The screen around it is the CRM's own (VaultAppScreen).

/// How the web Vault is opened inside the app: the page is loaded with `?embed=1`, announces that it
/// is ready, and is handed the key by a posted message (the web Vault's own embed protocol, version 1).
/// The key is never in the address, and the page does not store it.
enum WebVault {
    /// The host that answers the embed handshake. Tried on 14 November 2026: dev.vault.sgraph.ai does,
    /// vault.sgraph.ai does not yet.
    static let address = URL(string: "https://dev.vault.sgraph.ai/en-gb/vault/?embed=1")!
    static let handler = "sgit"

    /// Which page of the web Vault: the vault's own app, or the file browser. Tried on 15 November 2026:
    /// the page decides, not the message's `mode` (the file browser ignores it, the app page runs the app
    /// either way), and the app page, given a vault with no app, goes to the empty sign-in page and the key
    /// is lost; the app notices that and switches to the file browser.
    enum Surface: String, Equatable, Sendable {
        case app, files

        var address: URL {
            URL(string: self == .app ? "https://dev.vault.sgraph.ai/en-gb/app/?embed=1" : "https://dev.vault.sgraph.ai/en-gb/vault/?embed=1")!
        }
        /// As the embed protocol names it ("auto" picks the app when there is one).
        var mode: String { self == .app ? "auto" : "vault" }
    }

    /// The page the app page goes to when the vault has no app: the file browser's sign-in, outside embed mode.
    static func leftEmbed(_ url: URL?) -> Bool {
        guard let url, staysInside(url) else { return false }
        return url.path().hasPrefix("/en-gb/vault") && !(url.query() ?? "").contains("embed=1")
    }

    /// Where a vault opens first: its own app when it has one (`app.json` at the top or in `.vault/`), a
    /// page called index.html at the top shown in the file browser, or the file browser. A vault whose files
    /// are not known here is tried in the app page first.
    static func start(for paths: [String]?, path: String) -> (surface: Surface, path: String) {
        guard path.isEmpty else { return (.files, path) }
        guard let paths else { return (.app, "") }
        if paths.contains("app.json") || paths.contains(".vault/app.json") { return (.app, "") }
        if paths.contains("index.html") { return (.files, "index.html") }
        return (.files, "")
    }

    /// Runs in the page before anything else: passes the web Vault's own announcements to the app.
    static let listener = """
    window.addEventListener('message', function (e) {
      var d = e.data;
      if (!d || typeof d.sg !== 'string') return;
      if (d.sg === 'vault-embed-ready' || d.sg === 'vault-ready' || d.sg === 'vault-error') {
        window.webkit.messageHandlers.sgit.postMessage({ sg: d.sg, name: String(d.vaultName || ''), files: Number(d.fileCount || 0), hasApp: !!d.hasApp, message: String(d.message || '') });
      }
    });
    """

    /// Hands the page the key. `key` and `path` arrive as arguments, never as text in the script.
    static let open = "window.postMessage({ sg: 'vault-open', key: key, mode: mode, deepLink: path }, '*');"

    /// Gives the opened page the server's access key, which is what lets it save changes.
    static let allowChanges = """
    var shell = document.querySelector('vault-shell');
    if (shell) shell.dispatchEvent(new CustomEvent('vault-settings-access-key', { detail: { key: accessKey }, bubbles: true }));
    """

    /// Where the page may go: the web Vault itself. Anything else is opened outside the app.
    static func staysInside(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" { return true }
        return url.scheme == "https" && url.host() == address.host()
    }

    /// What the page said, in the app's words.
    static func standing(sg: String, name: String, files: Int, message: String) -> WebVaultModel.Standing? {
        switch sg {
        case "vault-embed-ready": return .waitingForKey
        case "vault-ready": return .open(files: files)
        case "vault-error": return .failed(message.isEmpty ? "The web Vault could not open this vault." : message)
        default: return nil
        }
    }
}

@MainActor
@Observable
final class WebVaultModel {
    enum Standing: Equatable {
        case loading
        case waitingForKey
        case open(files: Int)
        case failed(String)
    }
    var standing: Standing = .loading
    var changesAllowed = false
    /// What the page said when the vault opened: whether it has an app of its own.
    var hasApp = false
}

/// The web Vault in a web view that keeps nothing: no cookies, no storage, after it is closed.
struct WebVaultPage: UIViewRepresentable {
    let keyText: String
    let path: String
    var surface: WebVault.Surface = .files
    /// Called when the app page finds no app and leaves embed mode: the screen switches to the file browser.
    var noApp: () -> Void = {}
    /// The server's access key, handed over only when the person has asked to make changes there.
    let accessKey: String?
    let model: WebVaultModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.userContentController.add(context.coordinator, name: WebVault.handler)
        configuration.userContentController.addUserScript(
            WKUserScript(source: WebVault.listener, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: surface.address))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.page = self
        context.coordinator.allowChangesIfAsked(in: view)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: WebVault.handler)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var page: WebVaultPage
        private var keySent = false
        private var accessKeySent = false

        init(_ page: WebVaultPage) { self.page = page }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, WebVault.staysInside(message.frameInfo.request.url),
                  let body = message.body as? [String: Any], let sg = body["sg"] as? String,
                  let standing = WebVault.standing(sg: sg, name: body["name"] as? String ?? "",
                                                   files: body["files"] as? Int ?? 0,
                                                   message: body["message"] as? String ?? "") else { return }
            page.model.standing = standing
            if sg == "vault-ready", body["hasApp"] as? Bool == true { page.model.hasApp = true }
            guard let view = message.webView else { return }
            if standing == .waitingForKey { sendKey(to: view) }
            if case .open = standing { allowChangesIfAsked(in: view) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // The page announces itself when it is ready; if that was missed, the key is offered once more.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak webView] in
                guard let self, let webView, !self.keySent else { return }
                self.sendKey(to: webView)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            page.model.standing = .failed(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            page.model.standing = .failed(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Frames inside the page (a previewed HTML file) are the web Vault's own business.
            guard action.targetFrame?.isMainFrame ?? true else { return decisionHandler(.allow) }
            if page.surface == .app, WebVault.leftEmbed(action.request.url) {
                decisionHandler(.cancel)
                let noApp = page.noApp
                DispatchQueue.main.async { noApp() }
                return
            }
            if WebVault.staysInside(action.request.url) { return decisionHandler(.allow) }
            if let url = action.request.url, url.scheme == "https" { UIApplication.shared.open(url) }
            decisionHandler(.cancel)
        }

        private func sendKey(to view: WKWebView) {
            guard !keySent, WebVault.staysInside(view.url) else { return }
            keySent = true
            view.callAsyncJavaScript(WebVault.open, arguments: ["key": page.keyText, "path": page.path, "mode": page.surface.mode],
                                     in: nil, in: .page) { _ in }
        }

        func allowChangesIfAsked(in view: WKWebView) {
            guard page.model.changesAllowed, !accessKeySent, let accessKey = page.accessKey,
                  page.surface == .files, case .open = page.model.standing, WebVault.staysInside(view.url) else { return }
            accessKeySent = true
            view.callAsyncJavaScript(WebVault.allowChanges, arguments: ["accessKey": accessKey], in: nil, in: .page) { _ in }
        }
    }
}

