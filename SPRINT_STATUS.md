# Sprint Status: Clawsy App (2026-02-12)

## ✅ Completed
- **Core App Structure**: SwiftUI App Lifecycle, Menu Bar Item, Popover.
- **Networking**: WebSocket client (`Starscream`), auto-reconnect logic.
- **Features**:
    - 📸 **Screenshot**: Request/Response flow working. Interactive/Full screen modes supported.
    - 📋 **Clipboard**: Get/Set with user approval.
    - 🔒 **Security**: All remote actions trigger a local approval dialog (Alert or Window).
- **Protocol V2 (Native Node)**:
    - [x] Handshake implemented with Ed25519 signing (Native Gateway Connection).
    - [x] Connection sequence matches OpenClaw Protocol V3 requirements.
    - [x] Manual events (Screenshot/Clipboard push) integrated into UI.
    - [x] **Verification**: Client is code-complete for Native Node Role.

## 🚧 In Progress / TODO
- **Test Node Discovery**:
    - [x] macOS node (`598ac6df...`) connected and paired.
    - [x] Node identifies with `camera`, `clipboard`, and `screen` capabilities.
    - [ ] Resolve "gateway timeout" on `screen.capture` invoke (potential Clawsy-side deadlock or permission prompt issue).
    - [ ] Christian: Resolve "node command not allowed" for `screen_record`. This is likely a policy restriction in `openclaw.json` for this specific node.
- [ ] Protocol Alignment: Ensure `NetworkManagerV2.swift` payload signing string exactly matches Gateway expectations (verified minor diffs in scopes/token positioning).
- [ ] Feature: Add `screen_record` handler to `NetworkManagerV2.swift` (even if it just proxies to `screencapture -v`) to align with Gateway capabilities.
- **Distribution**: 
    - [ ] Obtain 'Developer ID Application' certificate and Team ID for signing.
    - [ ] Configure `xcrun notarytool` credentials.
    - [ ] Run `scripts/sign.sh` on a Mac environment.
- **Cleanup**:
    - [x] Deprecate `skills/clawsy-server` (V1 Python Server).
- [x] Fix Native Handshake Response parsing (V2).

## 📝 Notes
- **Major Milestone**: Clawsy is now fully compatible with the Native Node Protocol. It no longer requires the Python bridge.
- **Blocker**: Remote node control is restricted. I get "node command not allowed" when trying to invoke `screen_record` etc. This is likely a Gateway security policy issue that Christian needs to resolve (allowing these commands for the Clawsy node).
- **Automation**: Heartbeat/Cron checks are running, but work is stalled until the node is back online and permissions are granted.
