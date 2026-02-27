import Cocoa
import Social
import ClawsyShared

class ShareViewController: NSViewController {

    private let network = NetworkManager()

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        
        // Visual Background
        let visualEffect = NSVisualEffectView(frame: view.bounds)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        view.addSubview(visualEffect)
        
        // Header
        let label = NSTextField(labelWithString: NSLocalizedString("SENDING_TO_OPENCLAW", bundle: .clawsy, comment: ""))
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 140, width: 300, height: 20)
        view.addSubview(label)
        
        // Progress Indicator
        let progress = NSProgressIndicator(frame: NSRect(x: 130, y: 100, width: 40, height: 40))
        progress.style = .spinning
        progress.startAnimation(nil)
        view.addSubview(progress)

        self.view = view
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        
        guard let items = self.extensionContext?.inputItems as? [NSExtensionItem] else {
            self.cancel(nil)
            return
        }

        ShareHandler.handleSharedItems(items, network: network) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Success visual feedback (optional)
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                case .failure(let error):
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("SHARE_FAILED", bundle: .clawsy, comment: "")
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                    self.extensionContext?.cancelRequest(withError: error)
                }
            }
        }
    }

    func cancel(_ sender: AnyObject?) {
        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        self.extensionContext!.cancelRequest(withError: cancelError)
    }
}
