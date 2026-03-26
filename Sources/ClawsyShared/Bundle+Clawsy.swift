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

        // 2. Main bundle — build.sh copies lproj dirs into Contents/Resources/
        // so Bundle.main itself can resolve them via SwiftUI's locale mechanism
        if Bundle.main.localizedString(forKey: "APP_NAME", value: nil, table: nil) != "APP_NAME" {
            return .main
        }

        return .main
    }

    /// Locate the SPM-generated resource bundle for ClawsyShared.
    /// Returns the bundle itself — NOT an lproj sub-bundle.
    /// SwiftUI's LocalizedStringKey needs the parent bundle to resolve locales.
    private static func locateResourceBundle() -> Bundle? {
        let bundleName = "Clawsy_ClawsyShared"

        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
        ].compactMap { $0 }

        for base in candidates {
            let url = base.appendingPathComponent("\(bundleName).bundle")
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        return nil
    }
}
