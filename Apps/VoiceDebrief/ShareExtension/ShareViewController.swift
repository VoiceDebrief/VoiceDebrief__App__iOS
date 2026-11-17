import SwiftUI
import UIKit

/// The share extension's entry point (`NSExtensionPrincipalClass`): a small SwiftUI sheet on top of the
/// sending app. It only takes the file in; the app does the transcript and the debrief.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private var model: ShareModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        self.model = model
        let host = UIHostingController(rootView: ShareSheetView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}
