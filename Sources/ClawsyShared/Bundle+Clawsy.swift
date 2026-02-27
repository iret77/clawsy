import Foundation

public extension Bundle {
    /// Returns the bundle containing Clawsy's localized strings.
    ///
    /// In release builds, build.sh copies lproj directories into Contents/Resources/
    /// and Info.plist declares CFBundleDevelopmentRegion + CFBundleLocalizations,
    /// so Bundle.main resolves localized strings natively.
    ///
    /// In SPM debug builds, we fall back to the generated Clawsy_ClawsyShared.bundle.
    static var clawsy: Bundle {
        // Release builds: Bundle.main has our strings directly
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil {
            return .main
        }
        // SPM debug fallback
        let name = "Clawsy_ClawsyShared.bundle"
        for base in [Bundle.main.resourceURL, Bundle(for: _BundleToken.self).resourceURL].compactMap({ $0 }) {
            if let b = Bundle(url: base.appendingPathComponent(name)),
               b.path(forResource: "Localizable", ofType: "strings") != nil {
                return b
            }
        }
        return .main
    }
}

// Anchor class for bundle lookup — do not remove
private final class _BundleToken {}
