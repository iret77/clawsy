import Foundation

public extension Bundle {
    /// Returns the bundle containing Clawsy's localized strings.
    ///
    /// Strategy (release builds via build.sh):
    ///   build.sh copies lproj directories directly into Contents/Resources/
    ///   so Bundle.main resolves localized strings natively — no sub-bundle needed.
    ///
    /// Strategy (debug / SPM builds):
    ///   SPM generates Clawsy_ClawsyShared.bundle with lproj resources;
    ///   we locate it as a fallback.
    static var clawsy: Bundle {
        // Fast path: if Bundle.main already has our strings, use it.
        // This works in release .app bundles where build.sh copies lproj dirs
        // directly into Contents/Resources/.
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil {
            return .main
        }
        // Fallback: SPM-generated resource bundle (debug builds, or if main lookup fails)
        if let shared = findSharedBundle() {
            return shared
        }
        // Last resort — at least NSLocalizedString will return the key itself
        return .main
    }

    private static func findSharedBundle() -> Bundle? {
        let name = "Clawsy_ClawsyShared.bundle"
        let candidates: [URL] = [
            Bundle.main.resourceURL?.appendingPathComponent(name),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name)"),
            Bundle(for: _BundleToken.self).resourceURL?.appendingPathComponent(name),
            Bundle(for: _BundleToken.self).bundleURL.appendingPathComponent(name),
        ].compactMap { $0 }

        for url in candidates {
            if let bundle = Bundle(url: url) {
                // Accept the bundle if it has Localizable.strings in any localization
                if bundle.path(forResource: "Localizable", ofType: "strings") != nil
                    || bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en") != nil {
                    return bundle
                }
            }
        }
        return nil
    }
}

// Anchor class for bundle lookup — do not remove
private final class _BundleToken {}
