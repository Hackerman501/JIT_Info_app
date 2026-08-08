import SwiftUI

@main
struct JITInfoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(LanguageManager.shared)
        }
    }
}
