import SwiftUI

@main
struct ClaudeCreditWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // AppDelegate manages the menu bar item and the Settings window directly.
        // A no-op Settings scene keeps SwiftUI's App protocol happy.
        Settings { EmptyView() }
    }
}
