import Foundation
import Starscream

// MARK: - WebSocket Transport

/// Thin wrapper around Starscream WebSocket.
/// Single responsibility: open/close/send/receive.
/// No reconnect logic, no state management, no auth.
public final class WebSocketTransport: NSObject, WebSocketDelegate {

    // MARK: - Callbacks

    public var onConnected: (() -> Void)?
    public var onDisconnected: ((UInt16, String) -> Void)?
    public var onError: ((String) -> Void)?
    public var onMessage: ((String) -> Void)?
    public var onBinaryMessage: ((Data) -> Void)?

    // MARK: - State

    public private(set) var isOpen: Bool = false
    private var socket: WebSocket?
    private var watchdogTimer: Timer?
    private let watchdogTimeout: TimeInterval

    // MARK: - Init

    public init(watchdogTimeout: TimeInterval = 8.0) {
        self.watchdogTimeout = watchdogTimeout
        super.init()
    }

    // MARK: - Public API

    /// Open a WebSocket connection to the given URL.
    /// Only one connection at a time — calling this while connected
    /// will close the previous connection first.
    public func connect(to url: URL, timeout: TimeInterval? = nil, origin: String? = nil) {
        disconnect()

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout ?? watchdogTimeout
        if let origin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }

        let ws = WebSocket(request: request)
        ws.delegate = self
        self.socket = ws

        // Start watchdog timer
        let effectiveTimeout = timeout ?? watchdogTimeout
        DispatchQueue.main.async { [weak self] in
            self?.watchdogTimer?.invalidate()
            self?.watchdogTimer = Timer.scheduledTimer(
                withTimeInterval: effectiveTimeout,
                repeats: false
            ) { [weak self] _ in
                guard let self = self, !self.isOpen else { return }
                self.onError?("Connection timeout (\(Int(effectiveTimeout))s)")
                self.disconnect()
            }
        }

        ws.connect()
    }

    /// Close the WebSocket connection.
    public func disconnect() {
        DispatchQueue.main.async { [weak self] in
            self?.watchdogTimer?.invalidate()
            self?.watchdogTimer = nil
        }

        isOpen = false
        socket?.delegate = nil
        socket?.disconnect()
        socket = nil
    }

    /// Send a text message. Returns false if not connected.
    @discardableResult
    public func send(_ text: String) -> Bool {
        guard isOpen, let socket = socket else { return false }
        socket.write(string: text)
        return true
    }

    /// Send a binary message. Returns false if not connected.
    @discardableResult
    public func send(_ data: Data) -> Bool {
        guard isOpen, let socket = socket else { return false }
        socket.write(data: data)
        return true
    }

    /// Send a JSON-serializable dictionary. Returns false if not connected.
    @discardableResult
    public func sendJSON(_ dict: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return send(text)
    }

    // MARK: - WebSocketDelegate

    public func didReceive(event: WebSocketEvent, client: any WebSocketClient) {
        switch event {
        case .connected:
            DispatchQueue.main.async { [weak self] in
                self?.watchdogTimer?.invalidate()
                self?.watchdogTimer = nil
                self?.isOpen = true
                self?.onConnected?()
            }

        case .disconnected(let reason, let code):
            DispatchQueue.main.async { [weak self] in
                self?.isOpen = false
                self?.onDisconnected?(code, reason)
            }

        case .text(let text):
            DispatchQueue.main.async { [weak self] in
                self?.onMessage?(text)
            }

        case .binary(let data):
            DispatchQueue.main.async { [weak self] in
                self?.onBinaryMessage?(data)
            }

        case .cancelled:
            DispatchQueue.main.async { [weak self] in
                self?.isOpen = false
                self?.onDisconnected?(1000, "Cancelled")
            }

        case .error(let error):
            DispatchQueue.main.async { [weak self] in
                self?.isOpen = false
                self?.onError?(error?.localizedDescription ?? "Unknown WebSocket error")
            }

        case .peerClosed:
            DispatchQueue.main.async { [weak self] in
                self?.isOpen = false
                self?.onDisconnected?(1000, "Peer closed")
            }

        default:
            break
        }
    }
}
