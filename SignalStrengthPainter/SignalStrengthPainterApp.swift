import SwiftUI

@main
struct SignalStrengthPainterApp: App {
    @State private var showPaywall = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .fullScreenCover(isPresented: $showPaywall) {
                    PaywallView(isPresented: $showPaywall)
                }
        }
    }
}
