import Foundation

public extension Bundle {
    /// Returns the bundle containing Clawsy's localized strings.
    ///
    /// Localizable.strings are embedded in the ClawsyMac SPM target
    /// (Sources/ClawsyMac/Resources/{en,de}.lproj/) so SPM copies them
    /// directly into Bundle.main — no sub-bundle lookup needed.
    static var clawsy: Bundle { .main }
}
