# Sprint Status: Clawsy App (2026-02-13)

## ✅ Completed
- **Handshake V2**: Fully implemented and verified (hello-ok payload matching).
- **Branding/ID**: Aligned internal client ID with `openclaw-macos` for Gateway compatibility.
- **UI Redesign**: Native macOS Look & Feel (Vibrancy/Blur), refined typography, and shortcuts (⌘Q, ⌘,).
- **Diagnostics**: Integrated "Debug Log" window for RAW traffic inspection.
- **Permissions**: Confirmed TCC (Screen Recording) is active on Christian's Mac.

## 🚧 In Progress / TODO (Night Sprint)
- **Automatic SSH Fallback**: 
    - [ ] Implement connectivity check.
    - [ ] Add logic to launch `ssh -NT -L ...` automatically on connection failure.
- **File & Folder Sharing**:
    - [ ] Architect bidirectional sync (The Clawsy USP).
    - [ ] Implement `file.get` and `file.set` node commands.
- **Clipboard Preview**:
    - [ ] Add a dedicated UI component to preview incoming clipboard data.
- **Icon Refinement**:
    - [ ] Replace Emoji fallback with a monochrome outline Lobster icon (SF Symbol style).

## 📝 Notes
- **USP**: Clawsy focuses on professional workflow integration (File Sync, advanced Clipboard management) exceeding the standard companion app.
- **Verification**: christian will test the inbound `screen.capture` fix and the new UI in the morning.
