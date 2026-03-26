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
        // Build the Resources path from the executable location.
        // Executable: Clawsy.app/Contents/MacOS/Clawsy
        // Resources:  Clawsy.app/Contents/Resources/
        let execURL = Bundle.main.executableURL ?? Bundle.main.bundleURL
        let contentsURL = execURL
            .deletingLastPathComponent()  // → Contents/MacOS/
            .deletingLastPathComponent()  // → Contents/
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

        // 1. SPM resource bundle (contains lproj dirs — SwiftUI resolves locale)
        let spmURL = resourcesURL.appendingPathComponent("Clawsy_ClawsyShared.bundle")
        if let spmBundle = Bundle(url: spmURL),
           spmBundle.localizedString(forKey: "APP_NAME", value: "??", table: nil) != "??" {
            return spmBundle
        }

        // 2. Resources dir itself (build.sh copies lproj dirs there too)
        if let resBundle = Bundle(url: resourcesURL),
           resBundle.localizedString(forKey: "APP_NAME", value: "??", table: nil) != "??" {
            return resBundle
        }

        // 3. Bundle.main (last resort)
        if Bundle.main.localizedString(forKey: "APP_NAME", value: "??", table: nil) != "??" {
            return .main
        }

        // 4. Absolute fallback: try to find any lproj with our strings
        let fm = FileManager.default
        for lang in ["en", "de"] {
            let lprojURL = resourcesURL.appendingPathComponent("\(lang).lproj")
            if fm.fileExists(atPath: lprojURL.path),
               let lprojBundle = Bundle(url: lprojURL),
               lprojBundle.localizedString(forKey: "APP_NAME", value: "??", table: nil) != "??" {
                return lprojBundle
            }
        }

        return .main
    }
}
