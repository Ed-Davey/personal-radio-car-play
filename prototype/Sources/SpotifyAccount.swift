import CryptoKit
import Foundation
import Security

struct SpotifyAuthorizationRequest: Sendable {
    static let callbackScheme = "com.ed-davey.personalradio.spotify"
    static let redirectURI = "\(callbackScheme)://auth/callback"
    fileprivate static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    let authorizeURL: URL
    fileprivate let clientID: String
    fileprivate let verifier: String
    private let state: String

    init(clientID: String) throws {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty, clientID.unicodeScalars.allSatisfy(Self.unreserved.contains) else {
            throw SpotifyAccountError.invalidClientID
        }
        self.clientID = clientID
        verifier = try Self.randomValue()
        state = try Self.randomValue()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!.appending(queryItems: [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: "playlist-read-private"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state)
        ])
    }

    fileprivate func code(from callback: URL) throws -> String {
        guard callback.absoluteString.hasPrefix(Self.redirectURI + "?"),
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              components.fragment == nil, let items = components.queryItems else {
            throw SpotifyAccountError.invalidCallback
        }
        let states = items.filter { $0.name == "state" }
        let codes = items.filter { $0.name == "code" }
        let errors = items.filter { $0.name == "error" }
        guard states.count == 1, states[0].value == state, codes.count <= 1, errors.count <= 1 else {
            throw SpotifyAccountError.invalidCallback
        }
        if let error = errors.first, codes.isEmpty, let value = error.value, !value.isEmpty {
            throw value == "access_denied" ? SpotifyAccountError.authorizationDenied : .authorizationFailed
        }
        guard errors.isEmpty, let code = codes.first?.value, !code.isEmpty else {
            throw SpotifyAccountError.invalidCallback
        }
        return code
    }

    private static func randomValue() throws -> String {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw SpotifyAccountError.randomnessUnavailable }
        return base64URL(bytes)
    }

    private static func base64URL(_ bytes: Data) -> String {
        bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct SpotifyAccessToken: Sendable {
    fileprivate let value: String
    fileprivate let expiresAt: Date
}

struct SpotifyPlaylistPage: Equatable, Sendable {
    let items: [SpotifyPlaylist]
    let nextOffset: Int?
}

enum SpotifyAccountError: LocalizedError, Equatable, Sendable {
    case invalidClientID
    case randomnessUnavailable
    case invalidCallback
    case authorizationDenied
    case authorizationFailed
    case expiredToken
    case accessForbidden
    case rateLimited
    case invalidOffset
    case networkUnavailable
    case invalidResponse
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidClientID: "Spotify sign-in needs a Spotify app client ID."
        case .randomnessUnavailable: "Could not start a secure Spotify sign-in. Try again."
        case .invalidCallback: "Could not verify the Spotify sign-in. Start again."
        case .authorizationDenied: "Spotify playlist access was declined."
        case .authorizationFailed: "Spotify could not complete sign-in. Try again."
        case .expiredToken: "Your Spotify session has expired. Connect again."
        case .accessForbidden: "Spotify denied access. Check that your account can use this Spotify app."
        case .rateLimited: "Spotify is receiving too many requests. Wait a moment and try again."
        case .invalidOffset: "Spotify playlist paging reached its limit."
        case .networkUnavailable: "Could not reach Spotify. Check your connection and try again."
        case .invalidResponse: "Spotify returned a response Personal Radio could not read."
        case .serviceUnavailable: "Spotify could not complete the request. Try again."
        }
    }
}

actor SpotifyWebAPI {
    private static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!
    private static let playlistsURL = URL(string: "https://api.spotify.com/v1/me/playlists")!
    private static let pageSize = 50
    private static let maximumOffset = 100_000

    private static let directSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration, delegate: SpotifyRedirectBlocker(), delegateQueue: nil)
    }()

    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init() {
        transport = { request in try await Self.directSession.data(for: request) }
    }

    init(transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.transport = transport
    }

    func exchange(_ request: SpotifyAuthorizationRequest, callback: URL) async throws -> SpotifyAccessToken {
        let code = try request.code(from: callback)
        var tokenRequest = URLRequest(url: Self.tokenURL)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenRequest.httpBody = Self.formBody([
            ("grant_type", "authorization_code"),
            ("client_id", request.clientID),
            ("redirect_uri", SpotifyAuthorizationRequest.redirectURI),
            ("code", code),
            ("code_verifier", request.verifier)
        ])
        let value: TokenResponse = try await response(for: tokenRequest, isExchange: true)
        guard value.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame,
              value.expiresIn > 0, Self.isBearerToken(value.accessToken) else {
            throw SpotifyAccountError.invalidResponse
        }
        return SpotifyAccessToken(value: value.accessToken,
                                  expiresAt: Date.now.addingTimeInterval(TimeInterval(value.expiresIn)))
    }

    func playlists(using token: SpotifyAccessToken, offset: Int = 0) async throws -> SpotifyPlaylistPage {
        guard Date.now < token.expiresAt else { throw SpotifyAccountError.expiredToken }
        guard (0...Self.maximumOffset).contains(offset) else { throw SpotifyAccountError.invalidOffset }
        let url = Self.playlistsURL.appending(queryItems: [
            URLQueryItem(name: "limit", value: String(Self.pageSize)),
            URLQueryItem(name: "offset", value: String(offset))
        ])
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
        let page: PlaylistsResponse = try await response(for: request)
        guard page.items.count <= Self.pageSize else { throw SpotifyAccountError.invalidResponse }
        var seen: Set<String> = []
        let items = page.items.compactMap { item -> SpotifyPlaylist? in
            guard let id = item?.id, let name = item?.name,
                  let playlist = SpotifyPlaylist(id: id, name: name), seen.insert(id).inserted else { return nil }
            return playlist
        }

        // Only an indication that another page exists comes from the response.
        // Each request uses our fixed Spotify endpoint and locally calculated offset.
        let candidate = offset + Self.pageSize
        let hasNext = page.next?.isEmpty == false && candidate <= Self.maximumOffset
        return SpotifyPlaylistPage(items: items, nextOffset: hasNext ? candidate : nil)
    }

    private func response<Response: Decodable>(for request: URLRequest, isExchange: Bool = false) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await transport(request)
            try Task.checkCancellation()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SpotifyAccountError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse, http.url == request.url else {
            throw SpotifyAccountError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            guard let result = try? JSONDecoder().decode(Response.self, from: data) else {
                throw SpotifyAccountError.invalidResponse
            }
            return result
        case 300...399: throw SpotifyAccountError.invalidResponse
        case 400 where isExchange: throw SpotifyAccountError.authorizationFailed
        case 401: throw isExchange ? SpotifyAccountError.authorizationFailed : .expiredToken
        case 403: throw SpotifyAccountError.accessForbidden
        case 429: throw SpotifyAccountError.rateLimited
        default: throw SpotifyAccountError.serviceUnavailable
        }
    }

    private static func formBody(_ fields: [(String, String)]) -> Data {
        let allowed = SpotifyAuthorizationRequest.unreserved
        let pairs = fields.map { name, value in
            name + "=" + value.addingPercentEncoding(withAllowedCharacters: allowed)!
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    private static func isBearerToken(_ value: String) -> Bool {
        let unpadded = value.prefix(while: { $0 != "=" })
        let bearerCharacters = SpotifyAuthorizationRequest.unreserved.union(CharacterSet(charactersIn: "+/"))
        return !unpadded.isEmpty && unpadded.unicodeScalars.allSatisfy(bearerCharacters.contains)
            && value.dropFirst(unpadded.count).allSatisfy { $0 == "=" }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let tokenType: String
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
        }
    }

    private struct PlaylistsResponse: Decodable {
        struct Item: Decodable {
            let id: String?
            let name: String?
        }

        let items: [Item?]
        let next: String?
    }
}

private final class SpotifyRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
