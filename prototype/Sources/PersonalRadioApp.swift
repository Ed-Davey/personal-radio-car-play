import SwiftUI

@main
struct PersonalRadioApp: App {
    @State private var playback = PlaybackModel(mode: .pilot)
    @State private var spotifyPlaylists = SpotifyPlaylistLibrary()

    var body: some Scene {
        WindowGroup {
            PrototypeView(playback: playback, spotifyPlaylists: spotifyPlaylists)
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
