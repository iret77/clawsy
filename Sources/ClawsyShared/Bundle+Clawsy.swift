import Foundation

public extension Bundle {
    /// Returns the bundle containing Clawsy's localized strings.
    ///
    /// Search order:
    /// 1. SPM resource bundle (Clawsy_ClawsyShared.bundle) — contains the lproj dirs
    /// 2. Main bundle lproj (when build.sh copies strings into Contents/Resources/)
    /// 3. Main bundle as last resort
    static var clawsy: Bundle {
        // 1. SPM resource bundle (most reliable — SPM always generates this)
        if let spmBundle = locateResourceBundle() {
            return spmBundle
        }

        // 2. Main bundle lproj directories
        let preferred = Locale.preferredLanguages
            .map { $0.components(separatedBy: "-").first ?? $0 }
        for lang in preferred + ["en"] {
            if let url = Bundle.main.url(forResource: lang, withExtension: "lproj"),
               let bundle = Bundle(url: url) {
                // Verify this lproj actually contains our strings
                if bundle.localizedString(forKey: "APP_NAME", value: nil, table: nil) != "APP_NAME" {
                    return bundle
                }
            }
        }

        return .main
    }

    /// Locate the SPM-generated resource bundle for ClawsyShared.
    private static func locateResourceBundle() -> Bundle? {
        let bundleName = "Clawsy_ClawsyShared"

        // Check in main bundle's resource directory
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
            Bundle.main.resourceURL?.appendingPathComponent(".."),
        ].compactMap { $0 }

        for base in candidates {
            let url = base.appendingPathComponent("\(bundleName).bundle")
            if let bundle = Bundle(url: url) {
                // Find the correct lproj within
                let preferred = Locale.preferredLanguages
                    .map { $0.components(separatedBy: "-").first ?? $0 }
                for lang in preferred + ["en"] {
                    if let lprojURL = bundle.url(forResource: lang, withExtension: "lproj"),
                       let lprojBundle = Bundle(url: lprojURL) {
                        return lprojBundle
                    }
                }
                return bundle
            }
        }

        // Also check module bundle (for SPM debug runs and tests)
        #if swift(>=5.9)
        if let moduleBundle = Bundle(url: Bundle.main.bundleURL
            .appendingPathComponent("\(bundleName).bundle")) {
            return moduleBundle
        }
        #endif

        return nil
    }
}
