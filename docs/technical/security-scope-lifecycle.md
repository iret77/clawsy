# Technical Documentation: Security-Scoped Bookmark Lifecycle

This document details how Clawsy persists access to user-selected folders across app launches using macOS's security-scoped bookmarks. Understanding this lifecycle is critical for any developer working on features related to the shared folder.

## What are Security-Scoped Bookmarks?

Due to the macOS App Sandbox, an app cannot persistently access arbitrary file system locations. If a user selects a folder, the app loses access to it as soon as it's restarted.

To solve this, macOS provides "security-scoped bookmarks". These are small pieces of `Data` that securely encapsulate the permission to access a specific file or folder. By storing this bookmark data, the app can resolve it back into a usable URL and re-gain access after a restart.

## The Lifecycle in Clawsy

The entire logic is managed within `Sources/ClawsyShared/SharedConfig.swift`.

### 1. Storage

- When a user selects a shared folder in the UI, the app creates a security-scoped bookmark from the folder's URL.
- This bookmark (`Data`) is stored in `UserDefaults` under the key `sharedFolderBookmark`.

### 2. Resolving the Bookmark and Starting Access

Access is initiated via the static function `SharedConfig.resolveBookmark() -> URL?`. This function is the single source of truth for getting a usable URL for the shared folder.

Here's what it does on its **first call** during an app session:

1.  It retrieves the raw bookmark `Data` from `UserDefaults`.
2.  It calls `URL(resolvingBookmarkData:options:...)` with the `.withSecurityScope` option. This converts the data back into a URL but does not yet grant access.
3.  **Crucially, it calls `url.startAccessingSecurityScopedResource()`**. This is the call that asks the OS to enable Clawsy's permission to use the URL for this session.
4.  If access is granted, the function caches the resolved `URL` in a static variable `SharedConfig.resolvedFolderUrl`.
5.  The function then returns the URL.

On **subsequent calls** during the same app session, the function simply returns the cached URL from `SharedConfig.resolvedFolderUrl`, avoiding the overhead of re-resolving and re-starting access.

### 3. Ending Access

The `startAccessingSecurityScopedResource()` call must be balanced by a corresponding `stopAccessingSecurityScopedResource()` call to release the resource.

**This is the most critical part of the lifecycle:**

- The `stop` call is **not** automatically managed or paired with the `start` call (e.g., in a `defer` block).
- Access is explicitly stopped in other parts of the application when the resource is no longer needed.
- For example, `SettingsView.swift` calls `SharedConfig.resolvedFolderUrl?.stopAccessingSecurityScopedResource()` when the view disappears or a new folder is chosen.

### Risks and Developer Best Practices

The separation of `start` and `stop` creates a potential for resource leaks or premature access revocation.

- **Rule:** Any part of the code that uses the URL obtained from `resolveBookmark()` should be aware of this lifecycle.
- **Guideline:** If a piece of code is the "owner" of a specific, bounded access period, it is responsible for calling `stopAccessingSecurityScopedResource()` when it is finished.
- **Example:** A background file-watcher that uses the URL should not call `stop` until it is shut down, as this would prevent other parts of the app from using the URL. Conversely, a one-shot function that just lists the files should ideally `stop` access when it's done, but only if it can be sure no other part of the app is currently relying on that access.

Due to the static caching, the current implementation implies a **session-long access period** that is started on first use and (inconsistently) stopped when certain UI elements are dismissed. Developers should be extremely cautious when modifying this logic.
