# Clawsy Build Notes & Architecture

## Native Node Protocol (V2)
The current version of Clawsy implements the **OpenClaw Native Node Protocol (V3)**. This allows the app to connect directly to an OpenClaw Gateway as a first-class node, similar to how the `openclaw` CLI or other agent hosts connect.

### Key Components
- **NetworkManagerV2.swift**: Handles WebSocket connection, Ed25519 handshake (challenge/response), and command routing.
- **Protocol Flow**:
    1. Connect to Gateway (WebSocket).
    2. Receive `connect.challenge`.
    3. Sign payload `v2|deviceId|clientId|...|nonce` using local private key.
    4. Send `connect` request with signature.
    5. Register as `role: node` with capabilities `clipboard`, `screen`, and `camera`.

## Security & Privacy
- **Approval Flow**: All incoming commands (`screen.capture`, `clipboard.write`) require local user approval via SwiftUI alerts or the `ClipboardPreviewWindow`.
- **Identity**: Ed25519 keypairs are generated on first run. (TODO: Move to Keychain persistence).

## Build System
- **build.sh**: A script to package the Swift PM executable into a standard `.app` bundle.
- **Package.swift**: Defines dependencies (Starscream for WebSockets).
- **Architecture**: Universal binary (arm64 + x86_64).

## Current Status (2026-02-11)
- **Client**: Code-complete for V2.
- **Server**: Gateway connection verified via Python tests.
- **Next Step**: Compile on a Mac node to verify the Swift implementation of the protocol.
