import Cocoa
import Social
import ClawsyShared

class ShareViewController: NSViewController {

    private let network = NetworkManager()

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

        // Configure NetworkManager with credentials from shared App Group defaults
        let host = SharedConfig.serverHost
        let port = SharedConfig.serverPort
        let token = SharedConfig.serverToken
        let sshUser = SharedConfig.sshUser
        let useSsh = SharedConfig.useSshFallback

        guard !host.isEmpty, !token.isEmpty else {
            completeWithError(NSError(domain: "ai.clawsy", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Clawsy nicht konfiguriert. Bitte App öffnen und Einstellungen prüfen."]))
            return
        }

        guard let items = self.extensionContext?.inputItems as? [NSExtensionItem] else {
            cancel(nil); return
        }

        network.configure(host: host, port: port, token: token, sshUser: sshUser, fallback: useSsh)

        ShareHandler.handleSharedItems(items, network: network) { result in
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
