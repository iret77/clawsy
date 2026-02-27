import Foundation

public extension Bundle {
    static var clawsy: Bundle {
        // build.sh copies lproj dirs directly into Contents/Resources/ → Bundle.main finds them.
        // In SPM debug builds the strings live in the sub-bundle → fall back to it.
        // Strategy: try Bundle.main first (fast path for production app), then sub-bundle.
        if Bundle.main.path(forResource: "Localizable", ofType: "strings") != nil {
            return .main
        }

        let bundleName = "Clawsy_ClawsyShared.bundle"
        let candidates: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.url(forResource: "Clawsy_ClawsyShared", withExtension: "bundle")?.deletingLastPathComponent(),
        ]

        for candidate in candidates {
            if let url = candidate?.appendingPathComponent(bundleName),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }

        return .main // last-resort fallback
    }
}
