import Foundation

public extension Bundle {
    static var clawsy: Bundle {
        // 1. Try SPM-generated bundle (works in DEBUG + some Release configs)
        let bundleName = "Clawsy_ClawsyShared"
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("\(bundleName).bundle"),
            Bundle.main.bundleURL.appendingPathComponent("\(bundleName).bundle"),
            Bundle.main.resourceURL?.appendingPathComponent("Contents/Resources/\(bundleName).bundle"),
            Bundle(for: BundleLocator.self).resourceURL?.appendingPathComponent("\(bundleName).bundle"),
            Bundle(for: BundleLocator.self).bundleURL.appendingPathComponent("\(bundleName).bundle")
        ]

        for url in candidates.compactMap({ $0 }) {
            if let bundle = Bundle(url: url), bundle.resourceURL != nil {
                return bundle
            }
        }

        // 2. Fall back to main bundle — build.sh copies Localizable.strings
        //    directly into Contents/Resources/{en,de}.lproj/ so .main always works.
        return .main
    }
}

// Used only for bundle lookup — do not remove
private class BundleLocator {}
