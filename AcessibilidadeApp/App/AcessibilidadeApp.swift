import SwiftUI
import SwiftData

@main
struct AcessibilidadeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: AppSchema.models)
    }
}

