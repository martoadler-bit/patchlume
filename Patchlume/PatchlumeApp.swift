import SwiftUI

@main
struct PatchlumeApp: App {
    // Needed only for AirPlay/external-display support — see AppDelegate.swift.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
