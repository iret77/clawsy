import Foundation

public extension Bundle {
    /// Returns the bundle containing Clawsy's localized strings.
    ///
    /// SPM executables inside .app bundles have unreliable Bundle.main behavior.
    /// We resolve the path explicitly from the executable location:
    ///   Clawsy.app/Contents/MacOS/Clawsy → ../../Resources/Clawsy_ClawsyShared.bundle
    static var clawsy: Bundle {
        // Cache to avoid repeated filesystem lookups
        if let cached = _clawsyBundle { return cached }

        let bundle = resolveClawsyBundle()
        _clawsyBundle = bundle
        return bundle
    }

    private static var _clawsyBundle: Bundle?

    private static func resolveClawsyBundle() -> Bundle {
        // Try the ClawsyMac SPM resource bundle first — it has all lproj dirs
        // and SPM's Bundle.module resolves locale correctly.
        let candidates = [
            "Clawsy_ClawsyMac",
            "Clawsy_ClawsyShared"
        ]

        // Build the Resources path from the executable location.
        let execURL = Bundle.main.executableURL ?? Bundle.main.bundleURL
        let contentsURL = execURL
            .deletingLastPathComponent()  // → Contents/MacOS/
            .deletingLastPathComponent()  // → Contents/
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

        // 1. Try SPM resource bundles
        for name in candidates {
            let url = resourcesURL.appendingPathComponent("\(name).bundle")
            if let bundle = Bundle(url: url),
               bundle.localizedString(forKey: "APP_NAME", value: "??", table: nil) != "??" {
                return bundle
            }
        }

        // 2. Resources dir itself (build.sh copies lproj dirs there)
        if let resBundle = Bundle(url: resourcesURL),
           resBundle.localizedString(forKey: "APP_NAME", value: "??", table: nil) != "??" {
            return resBundle
        }

        // 3. Bundle.main
        if Bundle.main.localizedString(forKey: "APP_NAME", value: "??", table: nil) != "??" {
            return .main
        }

        return .main
    }
}
