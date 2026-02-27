import Foundation

public extension Bundle {
    /// Returns the bundle containing Clawsy's localized strings.
    ///
    /// In release builds, strings live in `Clawsy_ClawsyShared.bundle`
    /// which build.sh embeds into Contents/Resources/.
    /// Bundle.main is kept as last-resort fallback.
    static var clawsy: Bundle {
        #if DEBUG
        // Debug builds: SPM puts resources in Bundle.module, but .main works too
        return findSharedBundle() ?? .main
        #else
        // Release builds: must find Clawsy_ClawsyShared.bundle explicitly
        // because Bundle.main does not resolve lproj strings for SPM executables
        // packaged via custom build scripts.
        return findSharedBundle() ?? .main
        #endif
    }

    private static func findSharedBundle() -> Bundle? {
        let name = "Clawsy_ClawsyShared.bundle"
        let candidates: [URL] = [
            // Standard location when build.sh embeds it
            Bundle.main.resourceURL?.appendingPathComponent(name),
            // Fallback: next to the executable
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name)"),
            // SPM build directory (debug builds)
            Bundle(for: _BundleToken.self).resourceURL?.appendingPathComponent(name),
            Bundle(for: _BundleToken.self).bundleURL.appendingPathComponent(name),
        ].compactMap { $0 }

        for url in candidates {
            if let bundle = Bundle(url: url),
               bundle.path(forResource: "Localizable", ofType: "strings") != nil {
                return bundle
            }
        }
        return nil
    }
}

// Anchor class for bundle lookup — do not remove
private final class _BundleToken {}
