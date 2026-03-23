import Foundation
import os.log

#if os(macOS)

// MARK: - SSH Tunnel Manager

/// Manages the lifecycle of an SSH tunnel process on macOS.
/// Single responsibility: start tunnel, detect readiness, detect death.
/// No WebSocket logic, no reconnect logic, no state management.
public final class SSHTunnelManager {

    // MARK: - Callbacks

    public var onTunnelReady: ((UInt16) -> Void)?
    public var onTunnelFailed: ((String) -> Void)?
    public var onTunnelDied: (() -> Void)?
    public var onLog: ((String) -> Void)?

    // MARK: - State

    public private(set) var isRunning: Bool = false
    public private(set) var localPort: UInt16 = 0

    private var process: Process?
    private let logger = OSLog(subsystem: "ai.clawsy", category: "SSH")

    // MARK: - Configuration

    private let pollInterval: TimeInterval = 0.5
    private let tunnelTimeout: TimeInterval = 20.0

    // MARK: - Public API

    /// Start an SSH tunnel to the specified gateway.
    /// Calls `onTunnelReady` with the local port on success,
    /// or `onTunnelFailed` with a reason on failure.
    public func start(
        host: String,
        sshUser: String,
        gatewayPort: String = "18789"
    ) {
        // Stop any existing tunnel first
        stop()

        let (sshHost, sshPort) = parseSshHostAndPort(host)
        let targetPort = gatewayPort.isEmpty ? "18789" : gatewayPort

        guard !sshUser.isEmpty else {
            onTunnelFailed?("SSH user not configured")
            return
        }

        // Find a free local port
        guard let freePort = findFreePort() else {
            onTunnelFailed?("Could not find free local port")
            return
        }
        localPort = freePort

        log("Starting tunnel \(sshUser)@\(sshHost):\(sshPort) → 127.0.0.1:\(localPort) → 127.0.0.1:\(targetPort)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.launchTunnel(
                sshHost: sshHost,
                sshPort: sshPort,
                sshUser: sshUser,
                localPort: freePort,
                targetPort: targetPort
            )
        }
    }

    /// Stop the SSH tunnel process.
    public func stop() {
        guard let proc = process else { return }
        log("Stopping tunnel (PID \(proc.processIdentifier))")

        process = nil
        isRunning = false
        localPort = 0

        if proc.isRunning {
            proc.terminate()
            // Give it a moment, then force kill
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                if proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                }
            }
        }
    }

    deinit {
        stop()
    }

    // MARK: - Private

    private func launchTunnel(
        sshHost: String,
        sshPort: String,
        sshUser: String,
        localPort: UInt16,
        targetPort: String
    ) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        proc.arguments = [
            "-N", "-T",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes",
            "-p", sshPort,
            "-L", "127.0.0.1:\(localPort):127.0.0.1:\(targetPort)",
            "\(sshUser)@\(sshHost)"
        ]

        let errorPipe = Pipe()
        proc.standardError = errorPipe
        proc.standardOutput = FileHandle.nullDevice

        do {
            try proc.run()
            self.process = proc
        } catch {
            DispatchQueue.main.async {
                self.onTunnelFailed?("Failed to launch SSH: \(error.localizedDescription)")
            }
            return
        }

        // Poll until the tunnel port accepts connections
        let deadline = Date().addingTimeInterval(tunnelTimeout)
        var tunnelReady = false

        while Date() < deadline {
            Thread.sleep(forTimeInterval: pollInterval)

            guard proc.isRunning else { break }

            if isTcpPortOpen(host: "127.0.0.1", port: localPort) {
                tunnelReady = true
                break
            }
        }

        if tunnelReady {
            log("Tunnel ready on 127.0.0.1:\(localPort)")
            isRunning = true
            monitorProcess(proc)

            DispatchQueue.main.async {
                self.onTunnelReady?(localPort)
            }
        } else {
            let errData = errorPipe.fileHandleForReading.availableData
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
            let reason = proc.isRunning
                ? "Port \(localPort) never opened (timeout \(Int(tunnelTimeout))s)"
                : "SSH exited (code \(proc.terminationStatus)): \(errStr)"

            log("Tunnel failed: \(reason)")
            isRunning = false
            self.process = nil

            DispatchQueue.main.async {
                self.onTunnelFailed?(reason)
            }
        }
    }

    /// Monitor the SSH process for unexpected termination.
    private func monitorProcess(_ proc: Process) {
        proc.terminationHandler = { [weak self] terminatedProc in
            guard let self = self else { return }
            // Only fire if this is still our active process
            guard self.process === terminatedProc else { return }
            self.log("Tunnel died (exit code \(terminatedProc.terminationStatus))")
            self.isRunning = false
            self.process = nil
            DispatchQueue.main.async {
                self.onTunnelDied?()
            }
        }
    }

    // MARK: - Port Utilities

    /// Check if a TCP port is accepting connections (with 400ms timeout).
    private func isTcpPortOpen(host: String, port: UInt16) -> Bool {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { Darwin.close(sock) }

        var tv = timeval(tv_sec: 0, tv_usec: 400_000)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(host)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        } == 0
    }

    /// Find a free TCP port by binding to port 0.
    private func findFreePort() -> UInt16? {
        let sock = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return nil }
        defer { Darwin.close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return nil }

        var assignedAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &assignedAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(sock, $0, &len)
            }
        }
        guard got == 0 else { return nil }
        return UInt16(bigEndian: assignedAddr.sin_port)
    }

    /// Parse "host:port" syntax common in SSH config.
    private func parseSshHostAndPort(_ host: String) -> (host: String, port: String) {
        let parts = host.split(separator: ":")
        if parts.count == 2, let p = Int(parts[1]), p > 0, p < 65536 {
            return (String(parts[0]), String(p))
        }
        return (host, "22")
    }

    private func log(_ message: String) {
        os_log("[SSH] %{public}@", log: logger, type: .info, message)
        onLog?("[SSH] \(message)")
    }
}

#endif
