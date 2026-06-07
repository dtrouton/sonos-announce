import SwiftUI

@main
struct SonosAnnounceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            TextEditingCommands()
        }
    }
}
