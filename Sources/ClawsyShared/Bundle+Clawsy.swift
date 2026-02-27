import Foundation

public extension Bundle {
    /// Public alias for `Bundle.module` — the SPM-generated resource bundle for ClawsyShared.
    ///
    /// `Bundle.module` is synthesized by SPM for any target that has resources.
    /// It uses `Bundle(for: BundleToken.self)` internally, which correctly locates
    /// the bundle in all build environments (SPM debug, manual build.sh, update-installed).
    ///
    /// build.sh additionally copies lproj dirs into Contents/Resources/ AND compiles
    /// the .strings files to binary plist inside Clawsy_ClawsyShared.bundle via plutil.
    static var clawsy: Bundle { .module }
}
