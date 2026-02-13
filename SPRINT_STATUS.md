# Sprint Status: Clawsy App (2026-02-13)

## ✅ Completed
- **Handshake V2**: Fully implemented and verified (hello-ok payload matching).
- **Branding/ID**: Aligned internal client ID with `openclaw-macos` for Gateway compatibility.
- **UI Redesign**: Native macOS Look & Feel (Vibrancy/Blur), refined typography, and shortcuts (⌘Q, ⌘,).
- **Diagnostics**: Integrated "Debug Log" window for RAW traffic inspection.
- **Permissions**: Confirmed TCC (Screen Recording) is active on Christian's Mac.
- **Automatic SSH Fallback**: Implemented logic to auto-tunnel port 18789 via SSH on connection failure.
- **Bidirectional File Sync**: Core logic for 'file.list', 'file.get', and 'file.set' integrated with local HUD alerts.
- **Permission Duration**: Added "Allow for 1h" and "Allow for rest of day" options to File Sync HUD (Christian's Request).
- **Notifications**: Integrated macOS UNUserNotificationCenter. Displays notifications for all File Sync actions. 
- **Auto-Revoke**: Notifications for automated syncs (during "Allow" periods) include a "Revoke Permissions" button to immediately cancel active temporary permissions.
- **Localization**: Implemented i18n support. Added base translations for English (EN), German (DE), French (FR), and Spanish (ES). Fallback defaults to EN.
- **Clipboard HUD**: Refined preview window with 'Copy Local' support.

## 🚧 In Progress / TODO
- **Icon Refinement**:
    - [x] Implemented SF Symbol fallback (`ant.fill`) as a placeholder until custom SVG/Asset is ready.
    - [x] Enabled `isTemplate = true` for automatic light/dark mode icon switching.
- **Distribution**: 
    - [ ] Obtain 'Developer ID Application' certificate and Team ID for signing.
    - [ ] Configure `xcrun notarytool` credentials.
    - [ ] Run `scripts/sign.sh` on a Mac environment.

## 📝 Notes
- **USP**: Clawsy focuses on professional workflow integration (File Sync, advanced Clipboard management) exceeding the standard companion app.
- **Night Sprint Concluded**: (2026-02-13 02:00 UTC) Major features for SSH Fallback and File Sync added.
- **Verification**: christian will test the inbound `screen.capture` fix and the new UI in the morning.
