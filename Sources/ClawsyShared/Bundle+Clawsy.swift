import Foundation

public extension Bundle {
    static var clawsy: Bundle {
        // Fallback logic for manual builds without standard SPM bundle accessors
        #if DEBUG
        return .main
        #else
        // Try to find the bundle manually if Bundle.module is missing or crashing
        let bundleName = "Clawsy_ClawsyShared.bundle"
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.url(forResource: "Clawsy_ClawsyShared", withExtension: "bundle")?.deletingLastPathComponent(),
            Bundle.main.url(forResource: "ClawsyMac", withExtension: "bundle")?.deletingLastPathComponent()
        ]
        
        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName)
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return bundle
            }
        }
        
        return .main // Desperate fallback
        #endif
    }
}
