import Foundation

public extension Bundle {
    /// Returns the bundle containing Clawsy's localized strings.
    /// build.sh copies all Localizable.strings directly into
    /// Contents/Resources/{en,de}.lproj/ so Bundle.main always has them.
    static var clawsy: Bundle { .main }
}
