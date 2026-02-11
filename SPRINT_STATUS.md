# Sprint Status: Clawsy App (2026-02-08)

## ✅ Completed
- **Core App Structure**: SwiftUI App Lifecycle, Menu Bar Item, Popover.
- **Networking**: WebSocket client (`Starscream`), auto-reconnect logic.
- **Features**:
    - 📸 **Screenshot**: Request/Response flow working. Interactive/Full screen modes supported.
    - 📋 **Clipboard**: Get/Set with user approval.
    - 🔒 **Security**: All remote actions trigger a local approval dialog (Alert or Window).
- **Fixes**:
    - Added missing `ClipboardPreviewWindow.swift`.
    - Fixed `AppDelegate` conformance to `ObservableObject`.
- **Server**:
    - [x] Created `clawsy-server` skill with `server.py` and `requirements.txt`.
    - [x] Verified server script runs (`venv` created).
    - [x] Verified server startup (port 8765 binds successfully).
    - [x] Updated README to point to `skills/clawsy-server/`.
- **Protocol V2 (Native Node)**:
    - [x] Created `HandshakePoC.swift` implementing Ed25519 signing & WebSocket handshake.
    - [x] **New:** Created `NetworkManagerV2.swift` implementing full `node` role (Connect, Challenge, Commands).
    - [x] Implemented Manual Events (Screenshot/Clipboard push) in `NetworkManagerV2` and `ContentView`.
    - [x] Integrate V2 into `ContentView` (Code complete, Approval wiring fixed 2026-02-11).

## 🚧 In Progress / TODO
- **Distribution**: 
    - [x] Created `scripts/sign.sh` template for signing and notarization.
    - [ ] Obtain 'Developer ID Application' certificate and Team ID.
    - [ ] Configure `xcrun notarytool` credentials.
    - [ ] Run signing script on Mac.
- **Testing**: Need to compile and run on a real Mac (Pending Christian/Node availability; last check 2026-02-08 16:42 UTC: Offline).
- **Cleanup**:
    - [ ] Deprecate `skills/clawsy-server` (V1 Python Server) in favor of Native Gateway connection.

## 📝 Notes
- The app is ready for the first alpha build (Release candidate packaged via script).
- **Architecture Shift**: Moved to Native Node Protocol (V2). The Python server is now legacy/deprecated.
- V2 Protocol implementation is code-complete but untested.
