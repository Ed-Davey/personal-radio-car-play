import AuthenticationServices
import SwiftUI
import UniformTypeIdentifiers

private let backdrop = Color(red: 0.043, green: 0.063, blue: 0.072)
private let panel = Color(red: 0.074, green: 0.103, blue: 0.118)
private let outline = Color.white.opacity(0.11)
private let muted = Color(red: 0.64, green: 0.71, blue: 0.73)
private let mint = Color(red: 0.68, green: 0.87, blue: 0.79)

struct PrototypeView: View {
    @Bindable var playback: PlaybackModel
    let spotifyPlaylists: SpotifyPlaylistLibrary
    @State private var importingFiles = false
    @State private var playlistMessage: String?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if playback.mode == .spotify {
                        card("Spotify playlists", symbol: "music.note.list") {
                            sourcePicker
                            Divider()
                            SpotifyPlaylistsView(library: spotifyPlaylists)
                        }
                    } else if geometry.size.width >= 900 {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(spacing: 18) {
                                player
                                queue
                            }
                            VStack(spacing: 18) {
                                controls
                                eventLog
                            }
                            .frame(width: 310)
                        }
                    } else {
                        player
                        controls
                        queue
                        eventLog
                    }
                }
                .frame(maxWidth: 1_160)
                .padding(.horizontal, geometry.size.width >= 900 ? 32 : 18)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .background(backdrop.ignoresSafeArea())
        .tint(mint)
        .fileImporter(isPresented: $importingFiles, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            Task { @MainActor in
                guard playback.canEditPlaylist, let playlist = playback.playlist else { return }
                do {
                    let tracks = try await playlist.importTracks(from: result.get())
                    playlistMessage = tracks.count == 1 ? "Added one track." : "Added \(tracks.count) tracks."
                } catch {
                    playlistMessage = error.localizedDescription
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(backdrop)
                .frame(width: 42, height: 42)
                .background(mint, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            Text("Personal Radio")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 10)
            Label(playback.mode == .pilot ? "Private pilot" : playback.mode.rawValue, systemImage: "internaldrive")
                .font(.caption.weight(.medium))
                .foregroundStyle(muted)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.white.opacity(0.055), in: Capsule())
        }
    }

    private var player: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Now playing")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(muted)
                Spacer()
                HStack(spacing: 7) {
                    Circle()
                        .fill(playback.isPlaying ? mint : muted)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(transportStatus)
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.08), in: Capsule())
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    artwork.frame(width: 156, height: 156)
                    playingDetails.frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 16) {
                    artwork.frame(height: 112)
                    playingDetails.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 7) {
                ProgressView(value: playback.progress)
                    .accessibilityLabel("Playback progress")
                    .accessibilityValue("\(formatDuration(playback.elapsed)) of \(formatDuration(playback.duration))")
                HStack {
                    Text(formatDuration(playback.elapsed))
                    Spacer()
                    Text(formatDuration(playback.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(muted)
                .accessibilityHidden(true)
            }

            HStack(spacing: 20) {
                transportButton("Restart session", symbol: "arrow.counterclockwise", action: playback.reset)
                    .help("Return to the beginning of the session")
                Button(action: playback.togglePlayback) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 67, height: 55)
                        .background(mint, in: RoundedRectangle(cornerRadius: 17))
                        .foregroundStyle(backdrop)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                .disabled(!playback.canPlay)
                #if os(macOS)
                .keyboardShortcut(.space, modifiers: [])
                #endif
                transportButton("Skip", symbol: "forward.end.fill", action: playback.skip)
                    .disabled(!playback.isPlaying && !playback.isPaused)
            }

            if playback.mode == .demo {
                HStack(spacing: 9) {
                    Image(systemName: "speaker.wave.2")
                        .foregroundStyle(muted)
                        .accessibilityHidden(true)
                    Slider(value: $playback.volume, in: 0...1) { Text("Volume") }
                        .labelsHidden()
                        .frame(maxWidth: 124)
                }
                .font(.caption)
            }

            if let error = playback.assetError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color(red: 1, green: 0.77, blue: 0.54))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [panel, Color(red: 0.087, green: 0.151, blue: 0.159)], startPoint: .bottom, endPoint: .topTrailing))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(outline))
        }
    }

    private var playingDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(phaseLabel)
                .font(.caption.weight(.semibold).monospaced())
                .tracking(0.7)
                .foregroundStyle(mint)
            Text(playback.currentTitle)
                .font(.system(.largeTitle, design: .default).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(playback.currentSubtitle)
                .font(.subheadline)
                .foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17)
                .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.35, blue: 0.34), Color(red: 0.06, green: 0.17, blue: 0.20)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { context, size in
                let lineCount = 11
                for index in 0..<lineCount {
                    let fraction = Double(index) / Double(lineCount - 1)
                    var wave = Path()
                    for xIndex in 0...48 {
                        let x = Double(xIndex) / 48
                        let ripple = sin(x * 5.6 + fraction * 3.7) * (0.1 + fraction * 0.08)
                        let point = CGPoint(x: x * size.width, y: (0.17 + fraction * 0.63 + ripple) * size.height)
                        if xIndex == 0 { wave.move(to: point) } else { wave.addLine(to: point) }
                    }
                    context.stroke(wave, with: .color(mint.opacity(0.10 + fraction * 0.19)), lineWidth: 1)
                }
            }
            Image(systemName: phaseIcon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(mint)
                .frame(width: 70, height: 70)
                .background(backdrop.opacity(0.79), in: Circle())
                .overlay(Circle().strokeBorder(mint.opacity(0.30)))
        }
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .accessibilityHidden(true)
    }

    private var controls: some View {
        card("Session controls", symbol: "slider.horizontal.3") {
            sourcePicker
            Divider()
            if playback.mode == .demo {
                Picker("Scenario", selection: Binding(get: { playback.scenario }, set: { playback.selectScenario($0) })) {
                    ForEach(PlaybackScenario.allCases) { scenario in
                        Text(scenario.rawValue).tag(scenario)
                    }
                }
                .pickerStyle(.menu)
                Text("Changing scenario restarts the session. Audio and road reports are sample material.")
                    .font(.caption)
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Hourly news", isOn: $playback.newsEnabled)
                Toggle("Cornwall roadworks", isOn: $playback.worksEnabled)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Simulated clock")
                        .font(.caption)
                        .foregroundStyle(muted)
                    Text(demoClock(playback.demoTime))
                        .font(.title3.monospacedDigit().weight(.medium))
                }
                Button(action: playback.stopForRouteChange) {
                    Label("Simulate car disconnect", systemImage: "cable.connector.slash")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(!playback.isPlaying)
            } else {
                playlistControls
            }
        }
    }

    private var sourcePicker: some View {
        Picker("Source", selection: Binding(get: { playback.mode }, set: { playback.selectMode($0) })) {
            ForEach(ListeningMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private var playlistControls: some View {
        if let playlist = playback.playlist {
            Button {
                importingFiles = true
            } label: {
                Label("Import music files", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(!playback.canEditPlaylist)
            if playlist.isImporting {
                ProgressView("Importing audio files")
            } else if playlist.tracks.isEmpty {
                Text("Add DRM-free audio files to start a session.")
                    .font(.caption)
                    .foregroundStyle(muted)
            } else if !playback.canEditPlaylist {
                Text("Restart the session to edit the playlist.")
                    .font(.caption)
                    .foregroundStyle(muted)
            }
            if !playlist.tracks.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { index, track in
                            HStack(spacing: 8) {
                                Text(track.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    changePlaylist { try playlist.move(from: IndexSet(integer: index), to: index - 1) }
                                } label: { Image(systemName: "chevron.up") }
                                .accessibilityLabel("Move \(track.title) up")
                                .disabled(index == 0)
                                Button {
                                    changePlaylist { try playlist.move(from: IndexSet(integer: index), to: index + 2) }
                                } label: { Image(systemName: "chevron.down") }
                                .accessibilityLabel("Move \(track.title) down")
                                .disabled(index == playlist.tracks.count - 1)
                                Button {
                                    changePlaylist { try playlist.remove(at: IndexSet(integer: index)) }
                                } label: { Image(systemName: "trash") }
                                .accessibilityLabel("Remove \(track.title) from playlist")
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(!playback.canEditPlaylist)
                }
                .frame(height: min(CGFloat(playlist.tracks.count) * 33, 180))
            }
            if let playlistMessage {
                Text(playlistMessage)
                    .font(.caption)
                    .foregroundStyle(muted)
            }
        } else if let error = playback.playlistLoadError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
        }
    }

    private func changePlaylist(_ change: () throws -> Void) {
        guard playback.canEditPlaylist else { return }
        do {
            try change()
            playlistMessage = nil
        } catch {
            playlistMessage = error.localizedDescription
        }
    }

    private var queue: some View {
        card("Up next", symbol: "list.bullet") {
            if playback.upcoming.isEmpty {
                Text(playback.canPlay ? "No more items this session." : "Import tracks to build your queue.")
                    .foregroundStyle(muted)
                    .font(.subheadline)
            }
            ForEach(Array(playback.upcoming.enumerated()), id: \.offset) { index, title in
                if index > 0 { Divider() }
                Text(title)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var eventLog: some View {
        card("Session log", symbol: "clock.arrow.circlepath") {
            if playback.phaseLog.isEmpty {
                Text("Events appear when you start playback.")
                    .foregroundStyle(muted)
                    .font(.caption)
            }
            if !playback.phaseLog.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(playback.phaseLog.reversed())) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(demoClock(event.time))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(muted)
                                Text(event.message)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(CGFloat(playback.phaseLog.count) * 24, 194))
            }
        }
    }

    private func card<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(panel)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(outline))
        }
    }

    private func transportButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 46, height: 43)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var transportStatus: String {
        if playback.isPlaying { return "Playing" }
        if playback.isPaused { return "Paused" }
        return "Ready"
    }

    private var phaseLabel: String {
        switch playback.currentKind {
        case .track: "MUSIC"
        case .announcement: "PRESENTER"
        case .news: "SAMPLE BULLETIN"
        case .travel: "SAMPLE ROADWORKS"
        case .idle: playback.mode == .demo ? "DEMO SESSION" : "PRIVATE PLAYLIST"
        }
    }

    private var phaseIcon: String {
        switch playback.currentKind {
        case .track: "music.note"
        case .announcement: "mic.fill"
        case .news: "newspaper"
        case .travel: "road.lanes"
        case .idle: "waveform"
        }
    }

    private func demoClock(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "en_GB"))
        style.timeZone = TimeZone(identifier: "Europe/London") ?? .gmt
        return date.formatted(style)
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let whole = Int(seconds)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

private struct SpotifyPlaylistsView: View {
    let library: SpotifyPlaylistLibrary

    @Environment(\.openURL) private var openURL
    @Environment(\.webAuthenticationSession) private var authentication
    @AppStorage("personalRadio.spotify.clientID") private var clientID = ""
    @State private var name = ""
    @State private var link = ""
    @State private var message: String?
    @State private var token: SpotifyAccessToken?
    @State private var accountPlaylists: [SpotifyPlaylist] = []
    @State private var nextOffset: Int?
    @State private var accountTask: Task<Void, Never>?
    @State private var api = SpotifyWebAPI()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a playlist while parked. Spotify handles playback and CarPlay controls.")
                .foregroundStyle(muted)
                .font(.subheadline)

            TextField("Playlist name (optional)", text: $name)
            TextField("Spotify playlist link or URI", text: $link)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            Button("Save playlist", action: saveLink)
                .buttonStyle(.borderedProminent)
                .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let message {
                Text(message)
                    .foregroundStyle(muted)
                    .font(.footnote)
            }

            if !library.playlists.isEmpty {
                Divider()
                Text("Saved playlists")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(library.playlists) { playlist in
                    playlistRow(playlist, isSaved: true)
                }
            }

            Divider()
            if token == nil {
                DisclosureGroup("Connect your Spotify library") {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Enter the public Client ID from your Spotify developer app. Connecting gives Personal Radio read-only access to your playlists.")
                            .font(.footnote)
                            .foregroundStyle(muted)
                        TextField("Spotify developer Client ID", text: $clientID)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        Button("Connect Spotify", action: connectAccount)
                            .buttonStyle(.bordered)
                            .disabled(accountTask != nil || clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.top, 6)
                }
            } else {
                connectedLibrary
            }
            if accountTask != nil {
                ProgressView("Loading Spotify playlists")
            }
        }
        .textFieldStyle(.roundedBorder)
        .onDisappear {
            accountTask?.cancel()
            clearAccount()
        }
    }

    private var connectedLibrary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("From Spotify")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button("Refresh playlists") { loadPage(append: false) }
                Button("Disconnect") { clearAccount() }
            }
            .buttonStyle(.bordered)
            .disabled(accountTask != nil)

            if accountPlaylists.isEmpty, accountTask == nil {
                Text("Spotify has no playlists to show.")
                    .foregroundStyle(muted)
            }
            ForEach(accountPlaylists) { playlist in
                playlistRow(playlist, isSaved: false)
            }
            if nextOffset != nil {
                Button("Load more playlists") { loadPage(append: true) }
                    .buttonStyle(.bordered)
                    .disabled(accountTask != nil)
            }
        }
    }

    private func playlistRow(_ playlist: SpotifyPlaylist, isSaved: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(playlist.name)
            HStack {
                Button("Open in Spotify") {
                    message = nil
                    openURL(playlist.url) { @Sendable accepted in
                        guard !accepted else { return }
                        Task { @MainActor in
                            message = "The playlist could not open. Check that Spotify or a browser is available."
                        }
                    }
                }
                .accessibilityLabel("Open \(playlist.name) in Spotify")

                if isSaved {
                    Button("Remove", role: .destructive) {
                        library.remove(playlist)
                        message = "Playlist removed from Personal Radio."
                    }
                    .accessibilityLabel("Remove saved playlist \(playlist.name)")
                } else {
                    Button("Save playlist") { save(name: playlist.name, link: playlist.url.absoluteString) }
                        .accessibilityLabel("Save playlist \(playlist.name)")
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveLink() {
        if save(name: name, link: link) {
            name = ""
            link = ""
        }
    }

    @discardableResult
    private func save(name: String, link: String) -> Bool {
        do {
            let saved = try library.save(name: name, link: link)
            message = "Saved \(saved.name)."
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    private func connectAccount() {
        startAccountWork {
            let request = try SpotifyAuthorizationRequest(clientID: clientID)
            let callback = try await authentication.authenticate(
                using: request.authorizeURL,
                callbackURLScheme: SpotifyAuthorizationRequest.callbackScheme,
                preferredBrowserSession: .ephemeral
            )
            try Task.checkCancellation()
            let authorized = try await api.exchange(request, callback: callback)
            try Task.checkCancellation()
            let page = try await api.playlists(using: authorized, offset: 0)
            try Task.checkCancellation()
            token = authorized
            showPage(page, append: false)
        }
    }

    private func loadPage(append: Bool) {
        guard let token, let offset = append ? nextOffset : 0 else { return }
        startAccountWork {
            let page = try await api.playlists(using: token, offset: offset)
            try Task.checkCancellation()
            showPage(page, append: append)
        }
    }

    private func startAccountWork(_ operation: @escaping @MainActor () async throws -> Void) {
        guard accountTask == nil else { return }
        message = nil
        accountTask = Task { @MainActor in
            defer { accountTask = nil }
            do {
                try await operation()
            } catch is CancellationError {
                return
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                return
            } catch let error as SpotifyAccountError {
                if error == .expiredToken { clearAccount() }
                message = error.localizedDescription
            } catch {
                message = "Spotify sign-in could not finish. Try connecting again."
            }
        }
    }

    private func showPage(_ page: SpotifyPlaylistPage, append: Bool) {
        if !append { accountPlaylists = [] }
        var seen = Set(accountPlaylists.map(\.id))
        accountPlaylists += page.items.filter { seen.insert($0.id).inserted }
        nextOffset = page.nextOffset
    }

    private func clearAccount() {
        token = nil
        accountPlaylists = []
        nextOffset = nil
        message = nil
    }
}
