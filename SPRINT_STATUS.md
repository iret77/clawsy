# Sprint Status: Clawsy App (2026-02-12 17:45 UTC)

## ✅ Completed
- **Core App Structure**: SwiftUI App Lifecycle, Menu Bar Item, Popover.
- **Networking**: WebSocket client (`Starscream`), auto-reconnect logic.
- **Protocol V2 (Native Node)**:
    - [x] Handshake implemented with Ed25519 signing (Native Gateway Connection).
    - [x] Connection sequence matches OpenClaw Protocol V3 requirements.
    - [x] **Verification**: Node `81b00b18` is ONLINE and PAIRED.
    - [x] **Event Loop**: "Send Clipboard" from the app works (Push events received).

## 🚧 In Progress / TODO
- **Critical: Command Deadlock/Timeout**:
    - [ ] `screen.capture` invoke times out (30s).
    - [ ] App status stuck on "Handshaking..." even though Gateway sees it as Online.
    - [ ] **Theory**: Swift `handleMessage` might be failing to parse the Gateway's `connect` response, preventing it from transitioning to `Online` state and thus not processing the `req` command loop correctly.
- **Feature Alignment**:
    - [ ] Add `screen_record` handler to `NetworkManagerV2.swift`.
- **Distribution**: 
    - [ ] Obtain 'Developer ID Application' certificate and Team ID for signing.
    - [ ] Configure `xcrun notarytool` credentials.
    - [ ] Run `scripts/sign.sh` on a Mac environment.

## 📝 Notes
- **Status Update**: Christian hat eine neue Version mit Handshake-Fixes gestartet. Der Node ist online, aber der Inbound-Kanal (Gateway -> App) hängt noch.
- **Next Step**: Debugging des Response-Parsings in `NetworkManagerV2.swift`. Ich vermute, dass das `result` Feld in der Gateway-Antwort anders strukturiert ist, als der Code erwartet.
