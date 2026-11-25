import Foundation
import Testing
@testable import PersonalRadioCore

@MainActor
struct SpotifyPlaylistsTests {
    private static let firstID = "3cEYpjA9oz9GiPac4AsH4n"
    private static let secondID = "37i9dQZF1DWXRqgorJj26U"
    private static let storageKey = "spotify.savedPlaylists"

    @Test("Share, localized and Spotify URI links use one canonical playlist URL")
    func normalizesPlaylistLinks() throws {
        try withDefaults { defaults in
            let library = SpotifyPlaylistLibrary(defaults: defaults)
            let expected = "https://open.spotify.com/playlist/\(Self.firstID)"
            let links = [
                "\n  \(expected)?si=share&pt=context#fragment\t",
                "HTTPS://OPEN.SPOTIFY.COM/intl-pt-BR/playlist/\(Self.firstID)/?si=share",
                "spotify:playlist:\(Self.firstID)",
            ]
            for link in links {
                let playlist = try library.save(name: "  Road trip ", link: link)
                #expect(playlist.id == Self.firstID)
                #expect(playlist.url.absoluteString == expected)
                #expect(playlist.name == "Road trip")
            }
            #expect(library.playlists.count == 1)
        }
    }

    @Test("Unsupported Spotify resources and ambiguous URL origins are rejected")
    func rejectsInvalidPlaylistLinks() throws {
        try withDefaults { defaults in
            let library = SpotifyPlaylistLibrary(defaults: defaults)
            let id = Self.firstID
            let invalidLinks = [
                "",
                "http://open.spotify.com/playlist/\(id)",
                "https://open.spotify.com.evil.example/playlist/\(id)",
                "https://evil.example/playlist/\(id)?source=https://open.spotify.com/",
                "https://user@open.spotify.com/playlist/\(id)",
                "https://open.spotify.com:443/playlist/\(id)",
                "https://open.spotify.com:/playlist/\(id)",
                "https://%6fpen.spotify.com/playlist/\(id)",
                "https://spotify.link/\(id)",
                "https://open.spotify.com/track/\(id)",
                "https://open.spotify.com/intl-/playlist/\(id)",
                "https://open.spotify.com/playlist//\(id)",
                "https://open.spotify.com/playlist/\(id)/another",
                "https://open.spotify.com/playlist/\(id)%2Ftrack",
                "spotify:track:\(id)",
                "spotify:playlist:\(id):extra",
                "spotify:playlist:\(id)?si=unexpected",
                "spotify:playlist:short",
                "spotify:playlist:\(id)_",
                "spotify:playlist:\(id.dropLast())é",
                id,
            ]
            for link in invalidLinks {
                #expect(throws: SpotifyPlaylistError.self, Comment(rawValue: link)) {
                    try library.save(name: "Example", link: link)
                }
            }
            #expect(library.playlists.isEmpty)
        }
    }

    @Test("Saved playlists keep their order and use one record per Spotify ID")
    func savesRenamesAndRemovesAcrossReopening() throws {
        try withDefaults { defaults in
            let library = SpotifyPlaylistLibrary(defaults: defaults)
            let first = try library.save(name: "First", link: "spotify:playlist:\(Self.firstID)")
            let second = try library.save(name: "", link: "spotify:playlist:\(Self.secondID)")
            #expect(second.name == "Spotify playlist")

            let renamed = try library.save(name: "Renamed", link: first.url.absoluteString)
            let unchanged = try library.save(name: " ", link: first.url.absoluteString)
            #expect(renamed.id == first.id)
            #expect(unchanged == renamed)

            let reopened = SpotifyPlaylistLibrary(defaults: defaults)
            #expect(reopened.playlists == [renamed, second])
            reopened.remove(first)
            reopened.remove(first)
            #expect(SpotifyPlaylistLibrary(defaults: defaults).playlists == [second])
        }
    }

    @Test("Malformed persisted entries cannot create a link or hide valid entries")
    func filtersMalformedPersistedEntries() throws {
        try withDefaults { defaults in
            let entries: [Any] = [
                ["id": "track/other", "name": "Invalid ID"],
                ["id": Self.firstID, "name": "  Original name "],
                ["id": Self.firstID, "name": "Duplicate should be ignored"],
                ["id": Self.secondID, "name": 3],
                ["id": Self.secondID, "name": " "],
                "not a dictionary",
            ]
            defaults.set(entries, forKey: Self.storageKey)

            let library = SpotifyPlaylistLibrary(defaults: defaults)
            #expect(library.playlists.map(\.id) == [Self.firstID, Self.secondID])
            #expect(library.playlists.map(\.name) == ["Original name", "Spotify playlist"])
            #expect(library.playlists.map(\.url.host) == ["open.spotify.com", "open.spotify.com"])
        }
    }

    @Test("A non-list stored value recovers when a playlist is saved")
    func recoversFromMalformedStoredValue() throws {
        try withDefaults { defaults in
            defaults.set("not a list", forKey: Self.storageKey)
            let library = SpotifyPlaylistLibrary(defaults: defaults)
            #expect(library.playlists.isEmpty)

            let playlist = try library.save(name: "Recovered", link: "spotify:playlist:\(Self.firstID)")
            #expect(SpotifyPlaylistLibrary(defaults: defaults).playlists == [playlist])
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "PersonalRadio.SpotifyPlaylistsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
