import SwiftUI

@main
struct PersonalRadioApp: App {
    @State private var playback = PlaybackModel(mode: .pilot)

    var body: some Scene {
        WindowGroup {
            PrototypeView(playback: playback)
                .preferredColorScheme(.dark)
                #if os(macOS)
                .frame(minWidth: 710, minHeight: 630)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1_110, height: 780)
        .windowToolbarStyle(.unifiedCompact)
        #endif
    }
}
