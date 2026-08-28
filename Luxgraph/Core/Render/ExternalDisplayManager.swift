import SwiftUI
import UIKit

/// Shared coordinator for the external-display window — a singleton
/// because it's built by `ExternalDisplaySceneDelegate`, which UIKit
/// instantiates itself (per `AppDelegate.application(_:configurationForConnecting:options:)`)
/// and hands no context to; this is the one place both that delegate and
/// `GraphViewModel`/`ContentView` can reach.
///
/// AirPlay specifically requires the modern per-scene approach (a
/// `UIWindowSceneSessionRoleExternalDisplay` scene, handled here) rather
/// than the older `UIScreen.didConnectNotification` + manually-placed
/// `UIWindow` pattern — that older approach still works for a WIRED
/// HDMI/Lightning adapter (iOS treats the plugged-in screen as a plain
/// `UIScreen` any app can grab), but for AirPlay, iOS only routes an app's
/// own separate window content to the receiver if the app claims the
/// external-display scene role; otherwise it falls back to mirroring the
/// whole device screen, controls included, silently — no error, no
/// warning, it just mirrors.
@MainActor
final class ExternalDisplayManager: ObservableObject {
    static let shared = ExternalDisplayManager()

    @Published private(set) var isConnected = false
    /// Set once by `GraphViewModel` right after it creates its
    /// `RenderEngine`, so whenever a scene actually connects, there's
    /// something real to show instead of a second, empty engine.
    var renderEngine: RenderEngine?

    private init() {}

    /// Called from `ExternalDisplaySceneDelegate.scene(_:willConnectTo:options:)`.
    func windowSceneConnected(_ windowScene: UIWindowScene) -> UIWindow {
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = UIHostingController(rootView:
            PreviewView(renderEngine: renderEngine ?? RenderEngine())
                .ignoresSafeArea()
                .background(Color.black)
        )
        window.makeKeyAndVisible()
        isConnected = true
        return window
    }

    /// Called from `ExternalDisplaySceneDelegate.sceneDidDisconnect(_:)`.
    func windowSceneDisconnected() {
        isConnected = false
    }
}
