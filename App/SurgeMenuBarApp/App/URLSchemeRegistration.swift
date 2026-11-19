import CoreServices
import Foundation

/// Claims the `surge://` scheme so a widget click can open the panel.
///
/// The app's Info.plist is generated from `project.yml`, which does not declare `CFBundleURLTypes`
/// yet, and that file is outside this target. Until packaging adds the declaration, the app
/// registers itself as the scheme's handler at launch. Moving to the plist entry removes this type.
enum URLSchemeRegistration {
    static let scheme = "surge"

    static func register() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleIdentifier as CFString)
    }
}
