import CryptoKit
import Foundation
import Testing
@testable import PersonalRadioCore

@Suite("Spotify account")
struct SpotifyAccountTests {
    private let clientID = "public-spotify-client"
    private let firstID = "37i9dQZF1DXcBWIGoYBM5M"
    private let secondID = "37i9dQZF1DWXRqgorJj26U"
    private let tokenJSON = #"{"access_token":"fixture-token","token_type":"Bearer","expires_in":3600}"#

    @Test("Each sign-in gets a fresh state and proof key, with playlist read access only")
    func authorizationURL() throws {
        let request = try SpotifyAuthorizationRequest(clientID: " \(clientID)\n")
        let next = try SpotifyAuthorizationRequest(clientID: clientID)
        let fields = try fields(in: request.authorizeURL)
        let nextFields = try self.fields(in: next.authorizeURL)
        let state = try #require(fields["state"])
        let challenge = try #require(fields["code_challenge"])

        #expect(request.authorizeURL.scheme == "https")
        #expect(request.authorizeURL.host() == "accounts.spotify.com")
        #expect(request.authorizeURL.path() == "/authorize")
        #expect(fields["client_id"] == clientID)
        #expect(fields["response_type"] == "code")
        #expect(fields["redirect_uri"] == "com.ed-davey.personalradio.spotify://auth/callback")
        #expect(fields["scope"] == "playlist-read-private playlist-read-collaborative")
        #expect(fields["code_challenge_method"] == "S256")
        #expect(fields["code_verifier"] == nil)
        #expect(fields["client_secret"] == nil)
        #expect(state.utf8.count == 43)
        #expect(challenge.utf8.count == 43)
        #expect(state != nextFields["state"])
        #expect(challenge != nextFields["code_challenge"])
        #expect(throws: SpotifyAccountError.invalidClientID) {
            try SpotifyAuthorizationRequest(clientID: "\n ")
        }
    }

    @Test("Playback consent adds only the two player scopes")
    func playbackAuthorization() throws {
        let request = try SpotifyAuthorizationRequest(clientID: clientID, enablePlayback: true)
        let scopes = try #require(try fields(in: request.authorizeURL)["scope"])
        #expect(Set(scopes.split(separator: " ").map(String.init)) == [
            "playlist-read-private", "playlist-read-collaborative",
            "user-read-playback-state", "user-modify-playback-state"
        ])
    }

    @Test("Play sends a playlist context and pause targets the active device")
    func playbackCommands() async throws {
        let playlist = try #require(SpotifyPlaylist(id: firstID, name: "Test playlist"))
        let api = SpotifyWebAPI { http in
            if http.url?.host() == "accounts.spotify.com" { return try response(to: http, json: tokenJSON) }
            #expect(http.url?.host() == "api.spotify.com")
            #expect(http.url?.query() == nil)
            #expect(http.httpMethod == "PUT")
            #expect(http.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            switch http.url?.path() {
            case "/v1/me/player/play":
                let body = try #require(http.httpBody)
                #expect(try JSONDecoder().decode([String: String].self, from: body) == [
                    "context_uri": "spotify:playlist:\(firstID)"
                ])
                #expect(http.value(forHTTPHeaderField: "Content-Type") == "application/json")
            case "/v1/me/player/pause":
                #expect(http.httpBody == nil)
            default:
                Issue.record("Unexpected Spotify player endpoint")
            }
            return try response(to: http, status: 204, json: "")
        }
        let request = try SpotifyAuthorizationRequest(clientID: clientID, enablePlayback: true)
        let token = try await api.exchange(request, callback: callback(for: request, suffix: "&code=fixture"))
        try await api.play(playlist, using: token)
        try await api.pause(using: token)
    }

    @Test("Playback state includes track details and Spotify artwork")
    func playbackMetadata() async throws {
        let api = SpotifyWebAPI { http in
            if http.url?.host() == "accounts.spotify.com" { return try response(to: http, json: tokenJSON) }
            #expect(http.url?.absoluteString == "https://api.spotify.com/v1/me/player")
            #expect(http.httpMethod == "GET")
            return try response(to: http, json: #"""
                {"is_playing":true,"device":{"name":"Test iPhone"},"item":{
                    "name":"Fixture song","artists":[{"name":"Fixture artist"}],
                    "album":{"images":[{"url":"https://evil.example/art.jpg"},{"url":"https://i.scdn.co/image/art"}]},
                    "external_urls":{"spotify":"https://open.spotify.com/track/fixture"}
                }}
                """#)
        }
        let request = try SpotifyAuthorizationRequest(clientID: clientID, enablePlayback: true)
        let token = try await api.exchange(request, callback: callback(for: request, suffix: "&code=fixture"))
        let state = try #require(try await api.currentPlayback(using: token))
        #expect(state.isPlaying)
        #expect(state.deviceName == "Test iPhone")
        #expect(state.title == "Fixture song")
        #expect(state.creator == "Fixture artist")
        #expect(state.artworkURL?.absoluteString == "https://i.scdn.co/image/art")
        #expect(state.itemURL?.host() == "open.spotify.com")
    }

    @Test("An idle device has no state, and an unavailable destination gives a recovery message")
    func unavailablePlayer() async throws {
        let api = SpotifyWebAPI { http in
            if http.url?.host() == "accounts.spotify.com" { return try response(to: http, json: tokenJSON) }
            return try response(to: http, status: http.httpMethod == "GET" ? 204 : 404, json: "")
        }
        let request = try SpotifyAuthorizationRequest(clientID: clientID, enablePlayback: true)
        let token = try await api.exchange(request, callback: callback(for: request, suffix: "&code=fixture"))
        #expect(try await api.currentPlayback(using: token) == nil)
        let playlist = try #require(SpotifyPlaylist(id: firstID, name: "Test playlist"))
        await #expect(throws: SpotifyAccountError.noPlaybackDevice) {
            try await api.play(playlist, using: token)
        }
    }

    @Test("The token exchange sends the original S256 verifier and correctly encodes the code")
    func tokenExchange() async throws {
        let request = try SpotifyAuthorizationRequest(clientID: clientID)
        let auth = try fields(in: request.authorizeURL)
        let callback = try callback(for: request, suffix: "&code=code%2B%26%3D%25")
        let api = SpotifyWebAPI { http in
            #expect(http.url?.absoluteString == "https://accounts.spotify.com/api/token")
            #expect(http.httpMethod == "POST")
            #expect(http.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
            #expect(http.value(forHTTPHeaderField: "Authorization") == nil)
            let body = try #require(http.httpBody)
            let query = try #require(URL(string: "https://accounts.spotify.com/?\(String(decoding: body, as: UTF8.self))"))
            let form = try fields(in: query)
            let verifier = try #require(form["code_verifier"])
            let digest = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            #expect(verifier.utf8.count == 43)
            #expect(digest == auth["code_challenge"])
            #expect(form["code"] == "code+&=%")
            #expect(form["client_id"] == clientID)
            #expect(form["grant_type"] == "authorization_code")
            #expect(form["redirect_uri"] == SpotifyAuthorizationRequest.redirectURI)
            #expect(form["client_secret"] == nil)
            return try response(to: http, json: tokenJSON)
        }
        _ = try await api.exchange(request, callback: callback)
    }

    @Test("Foreign callbacks, bad state, and ambiguous OAuth parameters never reach Spotify")
    func rejectsInvalidCallbacks() async throws {
        let request = try SpotifyAuthorizationRequest(clientID: clientID)
        let auth = try fields(in: request.authorizeURL)
        let state = try #require(auth["state"])
        let redirect = SpotifyAuthorizationRequest.redirectURI
        let query = "?state=\(state)&code=valid"
        let invalid = [
            "https://open.spotify.com/auth/callback\(query)",
            "\(SpotifyAuthorizationRequest.callbackScheme)://other/callback\(query)",
            "\(SpotifyAuthorizationRequest.callbackScheme)://auth:443/callback\(query)",
            "\(SpotifyAuthorizationRequest.callbackScheme)://user@auth/callback\(query)",
            "\(redirect)/\(query)",
            "\(redirect)\(query)#another-code",
            "\(redirect)?state=wrong&code=valid",
            "\(redirect)?code=valid",
            "\(redirect)?state=\(state)",
            "\(redirect)?state=\(state)&code=",
            "\(redirect)\(query)&%73tate=\(state)",
            "\(redirect)\(query)&code=other",
            "\(redirect)\(query)&error=access_denied",
            "\(redirect)?state=\(state)&error=access_denied&error=access_denied"
        ]
        let api = SpotifyWebAPI { _ in
            Issue.record("An invalid callback reached the network.")
            throw URLError(.badURL)
        }
        for value in invalid {
            let url = try #require(URL(string: value))
            await #expect(throws: SpotifyAccountError.invalidCallback) {
                try await api.exchange(request, callback: url)
            }
        }
        let declined = try callback(for: request, suffix: "&error=access_denied")
        await #expect(throws: SpotifyAccountError.authorizationDenied) {
            try await api.exchange(request, callback: declined)
        }
    }

    @Test("Playlist paging uses the fixed Spotify origin and canonical handoff URLs")
    func playlistPaging() async throws {
        let api = SpotifyWebAPI { http in
            if http.httpMethod == "POST" { return try response(to: http, json: tokenJSON) }
            let url = try #require(http.url)
            let query = try fields(in: url)
            #expect(url.scheme == "https")
            #expect(url.host() == "api.spotify.com")
            #expect(url.path() == "/v1/me/playlists")
            #expect(http.httpMethod == "GET")
            #expect(http.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            #expect(query["limit"] == "50")
            if query["offset"] == "0" {
                let page = """
                {"items":[
                    {"id":"\(firstID)","name":"Morning","external_urls":{"spotify":"https://example.com/"}},
                    {"id":"\(firstID)","name":"Duplicate"},
                    {"id":"../escape","name":"Invalid"},
                    null
                ],"next":"https://example.com/bad-origin"}
                """
                return try response(to: http, json: page)
            }
            #expect(query["offset"] == "50")
            return try response(to: http, json: #"{"items":[{"id":"\#(secondID)","name":"Evening"}],"next":null}"#)
        }
        let token = try await token(using: api)
        let first = try await api.playlists(using: token)
        #expect(first.items.map(\.name) == ["Morning"])
        #expect(first.items.first?.url.absoluteString == "https://open.spotify.com/playlist/\(firstID)")
        let nextOffset = try #require(first.nextOffset)
        #expect(nextOffset == 50)
        let second = try await api.playlists(using: token, offset: nextOffset)
        #expect(second.items.map(\.name) == ["Evening"])
        #expect(second.nextOffset == nil)
    }

    @Test("Playlist offsets stop at Spotify's documented maximum")
    func boundsPlaylistPaging() async throws {
        let api = SpotifyWebAPI { http in
            if http.httpMethod == "POST" { return try response(to: http, json: tokenJSON) }
            let url = try #require(http.url)
            #expect(try fields(in: url)["offset"] == "100000")
            return try response(to: http, json: #"{"items":[],"next":"https://api.spotify.com/another-page"}"#)
        }
        let token = try await token(using: api)
        let last = try await api.playlists(using: token, offset: 100_000)
        #expect(last.items.isEmpty)
        #expect(last.nextOffset == nil)
        await #expect(throws: SpotifyAccountError.invalidOffset) {
            try await api.playlists(using: token, offset: -1)
        }
        await #expect(throws: SpotifyAccountError.invalidOffset) {
            try await api.playlists(using: token, offset: 100_001)
        }
    }

    @Test("Spotify request errors return fixed messages", arguments: [
        (401, SpotifyAccountError.expiredToken), (403, .accessForbidden), (429, .rateLimited),
        (307, .invalidResponse), (500, .serviceUnavailable)
    ])
    func providerErrors(status: Int, expected: SpotifyAccountError) async throws {
        let api = SpotifyWebAPI { http in
            if http.httpMethod == "POST" { return try response(to: http, json: tokenJSON) }
            return try response(to: http, status: status, json: "Provider response containing private data")
        }
        let token = try await token(using: api)
        await #expect(throws: expected) { try await api.playlists(using: token) }
        #expect(expected.localizedDescription.contains("private data") == false)
    }

    @Test("Token responses with an unexpected origin, invalid token or invalid expiration are rejected")
    func rejectsInvalidTokens() async throws {
        let invalid = [
            (#"{"access_token":"token","token_type":"Bearer","expires_in":3600}"#, URL(string: "https://example.com/")),
            (#"{"access_token":"token\r\ninjected","token_type":"Bearer","expires_in":3600}"#, nil),
            (#"{"access_token":"token","token_type":"Basic","expires_in":3600}"#, nil),
            (#"{"access_token":"token","token_type":"Bearer","expires_in":0}"#, nil)
        ]
        for (json, origin) in invalid {
            let api = SpotifyWebAPI { http in try response(to: http, json: json, origin: origin) }
            await #expect(throws: SpotifyAccountError.invalidResponse) { try await token(using: api) }
        }
    }

    private func token(using api: SpotifyWebAPI) async throws -> SpotifyAccessToken {
        let request = try SpotifyAuthorizationRequest(clientID: clientID)
        let callback = try callback(for: request, suffix: "&code=test-code")
        return try await api.exchange(request, callback: callback)
    }

    private func callback(for request: SpotifyAuthorizationRequest, suffix: String) throws -> URL {
        let state = try #require(fields(in: request.authorizeURL)["state"])
        return try #require(URL(string: "\(SpotifyAuthorizationRequest.redirectURI)?state=\(state)\(suffix)"))
    }

    private func fields(in url: URL) throws -> [String: String] {
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    private func response(to request: URLRequest, status: Int = 200, json: String,
                          origin: URL? = nil) throws -> (Data, URLResponse) {
        let url = try #require(origin ?? request.url)
        let http = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (Data(json.utf8), http)
    }
}
