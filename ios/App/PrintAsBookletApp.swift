import SwiftUI

@main
struct PrintAsBookletApp: App {
    @StateObject private var model = AppModel(processor: LiveBookletProcessor())

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
