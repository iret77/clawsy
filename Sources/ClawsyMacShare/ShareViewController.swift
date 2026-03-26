import Cocoa
import Social
import ClawsyShared

class ShareViewController: NSViewController {

    private let poller = GatewayPoller()

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))

        let visualEffect = NSVisualEffectView(frame: view.bounds)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        view.addSubview(visualEffect)

        let label = NSTextField(labelWithString: NSLocalizedString("SENDING_TO_OPENCLAW", bundle: .clawsy, comment: ""))
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 140, width: 300, height: 20)
        view.addSubview(label)

        let progress = NSProgressIndicator(frame: NSRect(x: 130, y: 100, width: 40, height: 40))
        progress.style = .spinning
        progress.startAnimation(nil)
        view.addSubview(progress)

        self.view = view
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        let host = SharedConfig.serverHost
        let port = SharedConfig.serverPort
        let token = SharedConfig.serverToken

        guard !host.isEmpty, !token.isEmpty else {
            completeWithError(NSError(domain: "ai.clawsy", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Clawsy nicht konfiguriert. Bitte App öffnen und Einstellungen prüfen."]))
            return
        }

        guard let items = self.extensionContext?.inputItems as? [NSExtensionItem] else {
            cancel(nil); return
        }

        // Configure poller with gateway credentials from shared defaults
        let scheme = (host.contains("localhost") || host.contains("127.0.0.1")) ? "http" : "https"
        let baseURL = "\(scheme)://\(host):\(port)"
        poller.start(baseURL: baseURL, token: token)

        ShareHandler.handleSharedItems(items, poller: poller) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                case .failure(let error):
                    self.completeWithError(error)
                }
            }
        }
    }

    private func completeWithError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("SHARE_FAILED", bundle: .clawsy, comment: "")
        alert.informativeText = error.localizedDescription
        alert.runModal()
        self.extensionContext?.cancelRequest(withError: error)
    }

    func cancel(_ sender: AnyObject?) {
        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        self.extensionContext?.cancelRequest(withError: cancelError)
    }
}
