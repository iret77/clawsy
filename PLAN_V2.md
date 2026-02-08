# Clawsy v2 - Native OpenClaw Node

**Goal:** Transform Clawsy from a side-car app (Mac <-> Python <-> OpenClaw) into a **native OpenClaw Node**.

## Architecture Change

- **Old (v1):** Mac App (Swift) -> WebSocket (ws://host:8765) -> Python Server -> OpenClaw (via `system event` hook)
- **New (v2):** Mac App (Swift) -> WebSocket (ws://gateway:PORT) -> OpenClaw Gateway (Native Node Protocol)

## Benefits

1.  **Direct Control:** OpenClaw can use standard tools (`nodes.invoke`, `nodes.camera_snap`) to control the Mac.
2.  **No Python Server:** Simplifies deployment. The Mac App is standalone.
3.  **Full Features:** Clipboard read/write, Screenshots, Camera, Notifications - all native.
4.  **Security:** Uses standard OpenClaw Node Pairing (Ed25519 signatures).

## Implementation Plan

### Phase 1: The Handshake (Swift)
- [ ] Implement `WebSocket` client connecting to Gateway.
- [ ] Handle `connect.challenge` from Gateway.
- [ ] Generate Ed25519 keypair for device identity.
- [ ] Sign the challenge nonce.
- [ ] Send `connect` request with `role: "node"` and capabilities.

### Phase 2: Command Handling (Swift)
- [ ] Listen for `node.invoke` or `req` messages from Gateway.
- [ ] Implement command dispatcher:
    - `clipboard.read` -> `NSPasteboard`
    - `clipboard.write` -> `NSPasteboard`
    - `screen.capture` -> `Screencapture` (already have code)
    - `camera.snap` -> `AVFoundation` (future)
    - `system.notify` -> `UNUserNotificationCenter`

### Phase 3: UI & Settings
- [ ] Settings UI to enter Gateway URL & Token (initially).
- [ ] Display Pairing Status (Pending/Paired).
- [ ] QR Code scanning for easy pairing (future).

## Protocol Details (Reverse Engineered)

**Handshake Flow:**
1.  **Gateway:** `{"type": "event", "event": "connect.challenge", "payload": {"nonce": "...", "ts": ...}}`
2.  **Node:** Generates signature of `nonce` (or `id+nonce+ts` - TBD).
3.  **Node:** Sends `connect` request:
    ```json
    {
      "type": "req",
      "id": "1",
      "method": "connect",
      "params": {
        "role": "node",
        "device": {
          "id": "...",
          "publicKey": "...",
          "signature": "...",
          "nonce": "..."
        },
        "caps": ["clipboard", "screen"],
        "commands": ["clipboard.read", "clipboard.write", "screen.capture"]
      }
    }
    ```

## Next Steps

1.  Create a **Proof of Concept (PoC)** Swift file that just connects and handshakes.
2.  Verify we can "pair" it in OpenClaw (`openclaw nodes pending`).
