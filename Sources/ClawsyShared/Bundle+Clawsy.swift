import Foundation

/// Anchor class for `Bundle(for:)` — resolves to ClawsyShared.framework bundle
/// when built via Xcode, or to the SPM module when built via swift build.
private class BundleToken {}

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
        // 1. Xcode Framework bundle: ClawsyShared.framework contains the strings
        //    directly (when built via xcodebuild with project.yml)
        let frameworkBundle = Bundle(for: BundleToken.self)
        if frameworkBundle != Bundle.main && bundleHasStrings(frameworkBundle) {
            return frameworkBundle
        }

        // 2. SPM resource bundles (when built via swift build)
        let execURL = Bundle.main.executableURL ?? Bundle.main.bundleURL
        let contentsURL = execURL
            .deletingLastPathComponent()   // MacOS/
            .deletingLastPathComponent()   // Contents/
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

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

        // 3. Resources directory itself (build.sh copies lproj dirs there)
        if let resBundle = Bundle(url: resourcesURL), bundleHasStrings(resBundle) {
            return resBundle
        }

        // 4. Bundle.main as last resort
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
