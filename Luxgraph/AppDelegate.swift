import UIKit

/// The one piece of UIKit-lifecycle plumbing a pure-SwiftUI `App` needs for
/// external-display/AirPlay support. On iPhone, that scene's role is
/// `.windowExternalDisplayNonInteractive` — NOT `.windowExternalDisplay`
/// (a different, separate case iPhone never actually connects). Confirmed
/// working over both wired HDMI and AirPlay Screen Mirroring: this method
/// alone isn't enough to make iOS attempt the connection at all — the role
/// also needs a matching static declaration in Info.plist
/// (`UIApplicationSceneManifest > UISceneConfigurations >
/// UIWindowSceneSessionRoleExternalDisplayNonInteractive`, pointing at
/// `ExternalDisplaySceneDelegate`); returning a config for it here just
/// customizes a role iOS already knows the app supports.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            let config = UISceneConfiguration(name: "External Display", sessionRole: .windowExternalDisplayNonInteractive)
            config.delegateClass = ExternalDisplaySceneDelegate.self
            return config
        }
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
