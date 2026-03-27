import Foundation

public extension Bundle {
    /// Returns the bundle containing Clawsy's localized strings.
    ///
    /// SPM executables inside .app bundles have unreliable Bundle.main behavior.
    /// We resolve the path explicitly from the executable location:
    ///   Clawsy.app/Contents/MacOS/Clawsy → ../../Resources/Clawsy_ClawsyShared.bundle
    static var clawsy: Bundle {
        if let cached = _clawsyBundle { return cached }
        let bundle = resolveClawsyBundle()
        _clawsyBundle = bundle
        return bundle
    }

    private static var _clawsyBundle: Bundle?

    private static func resolveClawsyBundle() -> Bundle {
        // Build the Resources path from the executable location.
        // Clawsy.app/Contents/MacOS/Clawsy → up 2 → Contents → Resources
        let execURL = Bundle.main.executableURL ?? Bundle.main.bundleURL
        let contentsURL = execURL
            .deletingLastPathComponent()   // MacOS/
            .deletingLastPathComponent()   // Contents/
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

        // Try SPM resource bundles. The correct test is whether the bundle
        // has an lproj directory — NOT localizedString, which returns the
        // key itself when the string is missing (making the test always pass).
        let candidates = [
            "Clawsy_ClawsyShared",
            "Clawsy_ClawsyMac"
        ]

        for name in candidates {
            let url = resourcesURL.appendingPathComponent("\(name).bundle")
            if let bundle = Bundle(url: url), bundleHasStrings(bundle) {
                return bundle
            }
        }

        // Try the Resources directory itself (build.sh copies lproj dirs there)
        if let resBundle = Bundle(url: resourcesURL), bundleHasStrings(resBundle) {
            return resBundle
        }

        // Bundle.main as last resort
        if bundleHasStrings(.main) {
            return .main
        }

        return .main
    }

    /// Check if a bundle actually contains Localizable.strings by looking
    /// for the file on disk, not relying on localizedString() which
    /// returns the key when the string is missing.
    private static func bundleHasStrings(_ bundle: Bundle) -> Bool {
        // Check for en.lproj/Localizable.strings or Base.lproj
        if bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en") != nil {
            return true
        }
        if bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "Base") != nil {
            return true
        }
        // Also check without localization (flat bundle)
        if bundle.path(forResource: "Localizable", ofType: "strings") != nil {
            return true
        }
        return false
    }
}
