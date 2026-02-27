import Foundation

public extension Bundle {
    /// Returns the bundle containing Clawsy's localized strings and resources.
    ///
    /// build.sh places compiled en.lproj / de.lproj into Contents/Resources/ →
    /// Bundle.main is the correct source in production builds.
    /// SPM debug builds keep strings inside Clawsy_ClawsyShared.bundle → fallback.
    static var clawsy: Bundle {
        // Production path: lproj dirs are in Contents/Resources/ (= Bundle.main).
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil {
            return .main
        }

        // SPM / debug fallback: strings live inside the generated resource sub-bundle.
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Clawsy_ClawsyShared.bundle"),
            Bundle.main.bundleURL.appendingPathComponent("Clawsy_ClawsyShared.bundle"),
        ]
        for url in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: url),
               bundle.path(forResource: "Localizable", ofType: "strings") != nil {
                return bundle
            }
        }

        return .main
    }
}
