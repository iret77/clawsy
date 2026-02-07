# Sprint Status: Clawsy App (2026-02-07)

## ✅ Completed
- **Core App Structure**: SwiftUI App Lifecycle, Menu Bar Item, Popover.
- **Networking**: WebSocket client (`Starscream`), auto-reconnect logic.
- **Features**:
    - 📸 **Screenshot**: Request/Response flow working. Interactive/Full screen modes supported.
    - 📋 **Clipboard**: Get/Set with user approval.
    - 🔒 **Security**: All remote actions trigger a local approval dialog (Alert or Window).
- **Fixes (Today)**:
    - Added missing `ClipboardPreviewWindow.swift`.
    - Fixed `AppDelegate` conformance to `ObservableObject`.
- **Server**:
    - [x] Created `clawsy-server` skill with `server.py` and `requirements.txt`.
    - [x] Verified server script runs (`venv` created).
    - [x] Updated README to point to `skills/clawsy-server/`.

## 🚧 In Progress / TODO
- **Testing**: Need to compile and run on a real Mac.
- **Distribution**: Need to sign and notarize the app for easy installation.

## 📝 Notes
- The app is ready for the first alpha build.
- Server is fully set up as a skill.
