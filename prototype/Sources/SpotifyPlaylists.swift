import Foundation
import Observation

struct SpotifyPlaylist: Identifiable, Equatable, Sendable {
    let id: String
    let name: String

    var url: URL {
        URL(string: "https://open.spotify.com/playlist/\(id)")!
    }

    init?(id: String, name: String) {
        guard Self.isPlaylistID(id) else { return nil }
        self.id = id
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmedName.isEmpty ? "Spotify playlist" : trimmedName
    }

    fileprivate static func id(from link: String) throws -> String {
        let input = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let uri = input.split(separator: ":", omittingEmptySubsequences: false)
        if uri.count == 3, uri[0].lowercased() == "spotify", uri[1] == "playlist",
           isPlaylistID(String(uri[2])) {
            return String(uri[2])
        }

        // Require the raw origin so encoded hosts, credentials and explicit
        // ports cannot normalize into an apparently valid Spotify URL.
        guard input.lowercased().hasPrefix("https://open.spotify.com/"),
              let components = URLComponents(string: input),
              components.percentEncodedHost?.lowercased() == "open.spotify.com" else {
            throw SpotifyPlaylistError.invalidLink
        }

        var path = components.percentEncodedPath
        if path.hasSuffix("/") { path.removeLast() }
        var parts = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 3,
           parts[0].range(of: #"^intl-[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$"#,
                          options: .regularExpression) != nil {
            parts.removeFirst()
        }
        guard parts.count == 2, parts[0] == "playlist", isPlaylistID(String(parts[1])) else {
            throw SpotifyPlaylistError.invalidLink
        }
        return String(parts[1])
    }

    static func isPlaylistID(_ id: String) -> Bool {
        id.utf8.count == 22 && id.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
        }
    }
}

enum SpotifyPlaylistError: LocalizedError {
    case invalidLink

    var errorDescription: String? {
        "Copy a playlist link from Spotify or enter a Spotify playlist URI."
    }
}

@MainActor
@Observable
final class SpotifyPlaylistLibrary {
    private static let storageKey = "spotify.savedPlaylists"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var playlists: [SpotifyPlaylist]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var saved: [SpotifyPlaylist] = []
        var seen: Set<String> = []
        for case let entry as [String: String] in defaults.array(forKey: Self.storageKey) ?? [] {
            guard let id = entry["id"], let name = entry["name"],
                  let playlist = SpotifyPlaylist(id: id, name: name),
                  seen.insert(id).inserted else { continue }
            saved.append(playlist)
        }
        playlists = saved
    }

    @discardableResult
    func save(name: String, link: String) throws -> SpotifyPlaylist {
        let id = try SpotifyPlaylist.id(from: link)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let index = playlists.firstIndex { $0.id == id }
        let existingName = index.map { playlists[$0].name }
        let chosenName = name.isEmpty ? existingName ?? "" : name
        guard let playlist = SpotifyPlaylist(id: id, name: chosenName) else {
            throw SpotifyPlaylistError.invalidLink
        }
        if let index {
            playlists[index] = playlist
        } else {
            playlists.append(playlist)
        }
        persist()
        return playlist
    }

    func remove(_ playlist: SpotifyPlaylist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists.remove(at: index)
        persist()
    }

    private func persist() {
        defaults.set(playlists.map { ["id": $0.id, "name": $0.name] }, forKey: Self.storageKey)
    }
}
