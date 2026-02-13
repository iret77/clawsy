# Sprint Status: Clawsy App (2026-02-13)

## ✅ Completed
- **Settings UI Refinement**: Replaced confusing icons with a prominent "Select Folder..." button. Added "Show in Finder" button that only appears after a path is set. Path display is now read-only for clarity. [Build #112]
- **Folder Picker Robustness**: Fixed `NSOpenPanel` issues where Christian couldn't change locations. Reconfigured panel with `resolvesAliases`, `canDownloadUbiquitousContents`, and `canResolveUbiquitousConflicts`. Ensured the picker runs on the main thread and uses `.becomeKey()` for focus. [Build #112]
- **Enhanced File Logging**: Added detailed `os_log` and `rawLog` tracking for `file.list` commands in `NetworkManagerV2` to diagnose potential timeouts. [Build #112]
- **Debug Log Reduction**: Significantly reduced log verbosity to show only major milestones (Connection status, SSH Tunneling, and File Sync triggers). Technical JSON dumps and redundant connection attempts are now handled via `os_log` only. [Build #111]
- **Finder Integration**: Added a "Reveal in Finder" button to the Settings menu, allowing users to quickly open the shared folder via `NSWorkspace`. [Build #111]
- **Automated Folder Monitoring**: Implemented `FileWatcher` using `DispatchSourceFileSystemObject` to monitor the shared folder for changes. The app now automatically triggers a sync event (`file.sync_triggered`) whenever a file is added/modified or upon successful connection, removing the need for a manual 'File Sync' button. [Build #111]
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
- **Localization**: Implemented i18n support. Added base translations for English (EN), German (DE), French (FR), and Spanish (ES). [DONE] Fallback defaults to EN.
- **Camera Preview Localization**: Fully localized Camera Preview UI and folder management strings across all supported languages (EN/DE/FR/ES). [DONE]
- **Camera Group**: Added "Camera" menu to UI for manual photo/list triggers.
- **Clipboard HUD**: Refined preview window with 'Copy Local' support.
- **Version bump**: Info.plist updated to 0.2.0.

## 🚧 In Progress / TODO
- **Production Readiness**:
    - [ ] Implement Sparkle or custom auto-update mechanism.
    - [ ] Create DMGs or PKG installers for easier distribution.
    - [ ] Enhance File Watcher performance for large directories (caching).

## 📝 Notes
- **USP**: Clawsy focuses on professional workflow integration (File Sync, advanced Clipboard management) exceeding the standard companion app.
- **Night Sprint Concluded**: (2026-02-13 19:45 UTC) Finalized ad-hoc signing script (`sign.sh`). All distribution and build scripts are now verified. Sprint tasks for the "Mac Companion Bridge" core are effectively complete for this phase. Build is ready for local installation via `install_clawsy.sh`.
- **Verification**: christian will test the inbound `screen.capture` fix and the new UI in the morning.
