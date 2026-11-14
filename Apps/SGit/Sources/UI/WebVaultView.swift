import Observation
import SwiftUI
import WebKit

/// How the web Vault is opened inside the app: the page is loaded with `?embed=1`, announces that it
/// is ready, and is handed the key by a posted message (the web Vault's own embed protocol, version 1).
/// The key is never in the address, and the page does not store it.
enum WebVault {
    /// The host that answers the embed handshake. Tried on 14 November 2026: dev.vault.sgraph.ai does,
    /// vault.sgraph.ai does not yet.
    static let address = URL(string: "https://dev.vault.sgraph.ai/en-gb/vault/?embed=1")!
    static let handler = "sgit"

    /// Runs in the page before anything else: passes the web Vault's own announcements to the app.
    static let listener = """
    window.addEventListener('message', function (e) {
      var d = e.data;
      if (!d || typeof d.sg !== 'string') return;
      if (d.sg === 'vault-embed-ready' || d.sg === 'vault-ready' || d.sg === 'vault-error') {
        window.webkit.messageHandlers.sgit.postMessage({ sg: d.sg, name: String(d.vaultName || ''), files: Number(d.fileCount || 0), message: String(d.message || '') });
      }
    });
    """

    /// Hands the page the key. `key` and `path` arrive as arguments, never as text in the script.
    static let open = "window.postMessage({ sg: 'vault-open', key: key, mode: 'vault', deepLink: path }, '*');"

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
}

/// The web Vault in a web view that keeps nothing: no cookies, no storage, after it is closed.
struct WebVaultPage: UIViewRepresentable {
    let keyText: String
    let path: String
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
        view.load(URLRequest(url: WebVault.address))
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
            if WebVault.staysInside(action.request.url) { return decisionHandler(.allow) }
            if let url = action.request.url, url.scheme == "https" { UIApplication.shared.open(url) }
            decisionHandler(.cancel)
        }

        private func sendKey(to view: WKWebView) {
            guard !keySent, WebVault.staysInside(view.url) else { return }
            keySent = true
            view.callAsyncJavaScript(WebVault.open, arguments: ["key": page.keyText, "path": page.path],
                                     in: nil, in: .page) { _ in }
        }

        func allowChangesIfAsked(in view: WKWebView) {
            guard page.model.changesAllowed, !accessKeySent, let accessKey = page.accessKey,
                  case .open = page.model.standing, WebVault.staysInside(view.url) else { return }
            accessKeySent = true
            view.callAsyncJavaScript(WebVault.allowChanges, arguments: ["accessKey": accessKey], in: nil, in: .page) { _ in }
        }
    }
}

/// The whole web Vault on the vault being looked at: everything it can do, without leaving the app.
struct WebVaultScreen: View {
    let shelf: VaultShelf
    let vault: SavedVault
    /// A file to open on, or the empty string for the vault's first screen.
    var path = ""
    @State private var model = WebVaultModel()
    @State private var asking = false
    @Environment(\.dismiss) private var dismiss

    private var hasLargeFiles: Bool { shelf.contents[vault.id]?.files.contains { $0.large } ?? false }
    private var canAllow: Bool { vault.canWrite && shelf.hasToken && !hasLargeFiles && !model.changesAllowed }

    var body: some View {
        NavigationStack {
            ZStack {
                WebVaultPage(keyText: vault.keyText, path: path, accessKey: shelf.accessKeyForTheWebVault, model: model)
                    .ignoresSafeArea(edges: .bottom)
                switch model.standing {
                case .loading, .waitingForKey:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(model.standing == .loading ? "Loading the web Vault" : "Opening the vault in it")
                            .font(.callout)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                case .failed(let why):
                    VStack(spacing: 10) {
                        ProblemLabel(text: "The web Vault did not open this vault.")
                        Text(why).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding()
                case .open:
                    EmptyView()
                }
            }
            .navigationTitle(model.changesAllowed ? "Web Vault: changes allowed" : "Web Vault: looking only")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if canAllow, case .open = model.standing {
                        Button("Allow changes") { asking = true }
                    }
                }
            }
            .confirmationDialog("Allow changes in the web Vault?", isPresented: $asking, titleVisibility: .visible) {
                Button("Allow changes") {
                    UsageLog.shared.action("web-vault.allow-changes")
                    model.changesAllowed = true
                }
                Button("Keep looking only", role: .cancel) {}
            } message: {
                Text("The web Vault can then edit, add, rename and delete in this vault, using this device's access key for \(shelf.serverName). Its changes are not signed by this device: History will show them as not signed. The access key is given to the page for this visit only and is forgotten when you press Done.")
            }
        }
    }
}
