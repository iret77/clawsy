import Foundation

public extension Bundle {
    /// Returns the bundle to use for Clawsy's localized strings.
    ///
    /// Classic macOS workaround: load the matching lproj directory as a Bundle directly.
    /// This bypasses NSBundle's localization-consistency check (which can silently fall back
    /// to the development language when it can't confirm the app supports a given locale).
    ///
    /// Ref: https://developer.apple.com/forums/thread/49909 (Quinn "The Eskimo", Apple DTS)
    static var clawsy: Bundle {
        // Try preferred languages in order, fall back to "en"
        let preferred = Locale.preferredLanguages
            .map { $0.components(separatedBy: "-").first ?? $0 }
        let candidates = preferred + ["en"]

        for lang in candidates {
            if let url = Bundle.main.url(forResource: lang, withExtension: "lproj"),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }

        // Sub-bundle fallback (SPM debug builds)
        let subBundleURL = Bundle.main.resourceURL?
            .appendingPathComponent("Clawsy_ClawsyShared.bundle")
        if let url = subBundleURL, let sub = Bundle(url: url) {
            return sub
        }

        return .main
    }
}
