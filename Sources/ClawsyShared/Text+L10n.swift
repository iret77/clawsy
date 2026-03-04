import SwiftUI

public extension Text {
    /// Creates a Text view from a localized string key using the Clawsy bundle.
    /// Use instead of `Text("KEY", bundle: .clawsy)` which has unreliable resolution.
    init(l10n key: String) {
        self.init(NSLocalizedString(key, bundle: .clawsy, comment: ""))
    }
}
