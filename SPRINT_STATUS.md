# Sprint Status: Clawsy App (2026-02-07)

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
- **Infrastructure**:
    - [x] Created `Info.plist` for proper macOS app bundling.
    - [x] Updated `build.sh` to package `.app` bundle (Release mode).
    - [x] Added Development instructions to README.

## 🚧 In Progress / TODO
- **Protocol V2 (Native Node)**:
    - [x] Created `HandshakePoC.swift` implementing Ed25519 signing & WebSocket handshake.
    - [ ] Compile and run `HandshakePoC` on macOS to verify connection.
    - [ ] Integrate into main `ClawsyApp` structure.
- **Testing**: Need to compile and run on a real Mac (Pending Christian/Node availability; last check 2026-02-08 12:43 UTC: Offline).
- **Server**: Verified active on Linux (restarted 2026-02-08 12:43 UTC).
- **Distribution**: 
    - [x] Created `scripts/sign.sh` template for signing and notarization.
    - [ ] Obtain 'Developer ID Application' certificate and Team ID.
    - [ ] Configure `xcrun notarytool` credentials.
    - [ ] Run signing script on Mac.

## 📝 Notes
- The app is ready for the first alpha build (Release candidate packaged via script).
- Server is fully set up as a skill.
