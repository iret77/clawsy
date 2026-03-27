import Foundation
import os.log

public extension Bundle {
    /// Returns the bundle containing Clawsy's localized strings.
    ///
    /// SPM executables inside .app bundles have unreliable Bundle.main behavior.
    /// We resolve from multiple sources to guarantee we find the strings.
    static var clawsy: Bundle {
        if let cached = _clawsyBundle { return cached }
        let bundle = resolveClawsyBundle()
        _clawsyBundle = bundle
        return bundle
    }

    private static var _clawsyBundle: Bundle?
    private static let bundleLog = OSLog(subsystem: "ai.clawsy", category: "Bundle")

    private static func resolveClawsyBundle() -> Bundle {
        // Strategy 1: ProcessInfo — most reliable for SPM executables in .app wrappers
        // ProcessInfo.processInfo.arguments[0] always returns the actual binary path.
        let resourcesURLs = buildResourcesCandidates()

        let bundleNames = [
            "Clawsy_ClawsyShared",
            "Clawsy_ClawsyMac"
        ]

        // Try each Resources dir × each bundle name
        for resourcesURL in resourcesURLs {
            for name in bundleNames {
                let url = resourcesURL.appendingPathComponent("\(name).bundle")
                if let bundle = Bundle(url: url), bundleHasStrings(bundle) {
                    os_log("L10n resolved: %{public}@", log: bundleLog, type: .info, url.path)
                    return bundle
                }
            }
        }

        // Try each Resources dir itself (build.sh copies lproj dirs there directly)
        for resourcesURL in resourcesURLs {
            if let resBundle = Bundle(url: resourcesURL), bundleHasStrings(resBundle) {
                os_log("L10n resolved (resources dir): %{public}@", log: bundleLog, type: .info, resourcesURL.path)
                return resBundle
            }
        }

        // Bundle.main as last resort
        if bundleHasStrings(.main) {
            os_log("L10n resolved: Bundle.main", log: bundleLog, type: .info)
            return .main
        }

        os_log("L10n FAILED — no bundle with strings found", log: bundleLog, type: .error)
        return .main
    }

    /// Build a list of candidate Resources directories from multiple sources.
    private static func buildResourcesCandidates() -> [URL] {
        var candidates: [URL] = []

        // 1. From ProcessInfo (most reliable for SPM executables)
        if let firstArg = ProcessInfo.processInfo.arguments.first {
            let execURL = URL(fileURLWithPath: firstArg).resolvingSymlinksInPath()
            let resources = execURL
                .deletingLastPathComponent()   // → MacOS/
                .deletingLastPathComponent()   // → Contents/
                .appendingPathComponent("Resources")
            candidates.append(resources)
        }

        // 2. From Bundle.main.executableURL
        if let execURL = Bundle.main.executableURL {
            let resources = execURL
                .deletingLastPathComponent()   // → MacOS/
                .deletingLastPathComponent()   // → Contents/
                .appendingPathComponent("Resources")
            if !candidates.contains(resources) {
                candidates.append(resources)
            }
        }

        // 3. Walk up from executable to find .app, then Contents/Resources
        if let firstArg = ProcessInfo.processInfo.arguments.first {
            var url = URL(fileURLWithPath: firstArg).resolvingSymlinksInPath()
            for _ in 0..<6 {
                url = url.deletingLastPathComponent()
                if url.pathExtension == "app" {
                    let resources = url.appendingPathComponent("Contents/Resources")
                    if !candidates.contains(resources) {
                        candidates.append(resources)
                    }
                    break
                }
            }
        }

        // 4. Bundle.main.resourceURL (works for Xcode builds)
        if let resURL = Bundle.main.resourceURL, !candidates.contains(resURL) {
            candidates.append(resURL)
        }

        return candidates
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
