# Sprint Status: Clawsy App (2026-02-12 18:58 UTC)

## ✅ Completed
- **Core App Structure**: SwiftUI App Lifecycle, Menu Bar Item, Popover.
- **Networking**: WebSocket client (`Starscream`), auto-reconnect logic.
- **Protocol V2 (Native Node)**:
    - [x] Handshake implemented with Ed25519 signing (Native Gateway Connection).
    - [x] Connection sequence matches OpenClaw Protocol V3 requirements.
    - [x] **Verification**: Node `32792d5a...` is ONLINE and PAIRED.
    - [x] **Event Loop**: "Send Clipboard" from the app works (Push events received).
- **Bug Fixes**:
    - [x] Refined `handleMessage` handshake logic to be more robust against variant response formats.

## 🚧 In Progress / TODO
- **Critical: Command Deadlock/Timeout**:
    - [ ] `screen.capture` invoke times out (30s) - Node is connected but command processing seems stuck on the app side or waiting for user interaction that isn't surfacing.
    - [ ] **Theory**: If the app is in the background or lack permissions (Accessibility/Screen Recording), `screencapture` might be hanging or returning nil without error.
- **Feature Alignment**:
    - [ ] Add `screen_record` handler to `NetworkManagerV2.swift`.
- **Distribution**: 
    - [ ] Obtain 'Developer ID Application' certificate and Team ID for signing.
    - [ ] Configure `xcrun notarytool` credentials.
    - [ ] Run `scripts/sign.sh` on a Mac environment.

## 📝 Notes
- **Status Update**: Node `32792d5a` ist verbunden und gepaart. Manuelle Events (Clipboard Push) funktionieren. Inbound Commands (`screen.capture`) lösen aktuell Timeouts aus.
- **Next Step**: Christian muss prüfen, ob auf dem Mac Berechtigungs-Dialoge (Screen Recording) im Hintergrund hängen oder ob `screencapture` Berechtigungen fehlen.
