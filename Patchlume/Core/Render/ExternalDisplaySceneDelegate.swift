import UIKit

/// Handles the lifecycle of the `windowExternalDisplayNonInteractive`-role scene UIKit
/// creates when AirPlay Screen Mirroring (or a wired external display)
/// connects. Registered via `AppDelegate.application(_:configurationForConnecting:options:)`
/// — UIKit instantiates this itself, so it has no way to receive the app's
/// `RenderEngine` directly; it goes through `ExternalDisplayManager.shared`
/// instead.
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Task { @MainActor in
            self.window = ExternalDisplayManager.shared.windowSceneConnected(windowScene)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Task { @MainActor in
            ExternalDisplayManager.shared.windowSceneDisconnected()
        }
    }
}
