import AVFoundation
import Foundation
import Observation

#if os(iOS)
import MediaPlayer
#endif

enum PlaybackKind: String {
    case track = "Music"
    case announcement = "Presenter"
    case news = "News"
    case travel = "Travel"
    case idle = "Ready"
}

enum PlaybackScenario: String, CaseIterable, Identifiable {
    case standard = "Normal bulletin"
    case lateNews = "Late bulletin"
    case expired = "Expired reports"
    case reopened = "Road reopened"

    var id: Self { self }
}

enum ListeningMode: String, CaseIterable, Identifiable {
    case pilot = "My playlist"
    case demo = "Sample demo"

    var id: Self { self }
}

struct PlaybackEvent: Identifiable {
    let id = UUID()
    let time: Date
    let message: String
}

private enum AudioSource {
    case fixture(String)
    case file(URL)
    case speech(String)
}

private struct SessionTrack {
    let title: String
    let artist: String?
    let source: AudioSource
    let introduction: AudioSource
}

private struct AudioSegment {
    let kind: PlaybackKind
    let title: String
    let subtitle: String
    let source: AudioSource
}

private final class AudioCompletion: NSObject, AVAudioPlayerDelegate {
    private let complete: @Sendable (Bool) -> Void

    init(complete: @escaping @Sendable (Bool) -> Void) {
        self.complete = complete
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        complete(flag)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        complete(false)
    }
}

private final class SpeechCompletion: NSObject, AVSpeechSynthesizerDelegate {
    private let complete: @Sendable (Bool) -> Void

    init(complete: @escaping @Sendable (Bool) -> Void) {
        self.complete = complete
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        complete(true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        complete(false)
    }
}

@MainActor @Observable final class PlaybackModel {
    private static let outputError = "Audio output could not start. Check the output and press Play to retry."
    private static let sessionError = "Audio session unavailable. Press Play to try again."

    private static let demoTracks = [
        (title: "Harbour Lights", artist: "The Breakwater Club"),
        (title: "Low Tide", artist: "Sundown Parcel"),
        (title: "Headland Air", artist: "North Marker")
    ].enumerated().map { index, song in
        SessionTrack(title: song.title, artist: song.artist, source: .fixture("track-\(index + 1)"),
                     introduction: .fixture("intro-\(index + 1)"))
    }

    // 18 November 2026, 10:00 GMT. The demonstration jumps to sample boundary
    // times so each scenario can be heard within one short listening session.
    private static let bulletinHour = Date(timeIntervalSince1970: 1_794_996_000)
    private static let startTime = bulletinHour.addingTimeInterval(-30)

    private(set) var currentTitle = "Ready to listen"
    private(set) var currentSubtitle = "Start your sample listening session."
    private(set) var currentKind = PlaybackKind.idle
    private(set) var isPlaying = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var demoTime = PlaybackModel.startTime
    private(set) var phaseLog: [PlaybackEvent] = []
    private(set) var scenario = PlaybackScenario.standard
    private(set) var assetError: String?
    private(set) var mode: ListeningMode
    let playlist: LocalPlaylist?
    let playlistLoadError: String?
    var worksEnabled = true
    var newsEnabled = true

    private var outputVolume: Double = 0.75
    var volume: Double {
        get { outputVolume }
        set {
            outputVolume = min(1, max(0, newValue))
            player?.volume = Float(outputVolume)
        }
    }

    var isPaused: Bool { !isPlaying && currentKind != .idle }
    var canEditPlaylist: Bool { currentKind == .idle && playlist?.isImporting == false }
    var canPlay: Bool {
        mode == .demo || isPlaying || isPaused || (canEditPlaylist && playlist?.tracks.isEmpty == false)
    }
    var progress: Double { duration > 0 ? min(1, elapsed / duration) : 0 }
    var upcoming: [String] {
        if currentKind == .idle {
            return completed && mode == .demo ? [] : selectedTracks.map(\.title)
        }
        if currentKind == .track {
            return sessionTracks.dropFirst(trackIndex + 1).map(\.title)
        }
        let reports = pending.filter {
            ($0.kind == .news && newsEnabled) || ($0.kind == .travel && worksEnabled)
        }
        return reports.map(\.title) + sessionTracks.dropFirst(trackIndex).map(\.title)
    }

    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var audioStart = PlaybackModel.startTime
    @ObservationIgnored private var playerID: UUID?
    @ObservationIgnored private var delegate: AudioCompletion?
    @ObservationIgnored private var speaker: AVSpeechSynthesizer?
    @ObservationIgnored private var speechDelegate: SpeechCompletion?
    @ObservationIgnored private var speechDeadline: Task<Void, Never>?
    @ObservationIgnored private var speechText: String?
    #if os(iOS)
    @ObservationIgnored private var hasActiveAudioSession = false
    #endif
    private var sessionTracks: [SessionTrack] = []
    private var trackIndex = 0
    private var pending: [AudioSegment] = []
    private var handledNews = false
    private var handledTravel = false
    private var loggedLateNews = false
    private var completed = false

    init(resourceBundle: Bundle = .main, mode: ListeningMode = .demo, playlistDirectory: URL? = nil) {
        bundle = resourceBundle
        self.mode = mode
        do {
            playlist = try LocalPlaylist(directory: playlistDirectory)
            playlistLoadError = nil
        } catch {
            playlist = nil
            playlistLoadError = error.localizedDescription
        }
        setReadyDisplay()
        #if os(iOS)
        registerSystemControls()
        #endif
    }

    func togglePlayback() {
        if isPlaying {
            pause("Paused")
        } else {
            play()
        }
    }

    func selectScenario(_ selection: PlaybackScenario) {
        scenario = selection
        reset()
    }

    func selectMode(_ selection: ListeningMode) {
        guard mode != selection else { return }
        mode = selection
        reset()
    }

    func reset() {
        discardPlayer()
        releaseAudioSession()
        pending = []
        sessionTracks = []
        trackIndex = 0
        handledNews = false
        handledTravel = false
        loggedLateNews = false
        completed = false
        assetError = nil
        phaseLog = []
        setReadyDisplay()
        publishNowPlaying()
    }

    func stopForRouteChange() {
        pause("Audio output changed. Press Play to continue.")
    }

    func skip() {
        guard currentKind != .idle else { return }
        let shouldPlay = isPlaying
        let skippingTrack = currentKind == .track
        record("Skipped \(currentTitle)")
        discardPlayer()
        if skippingTrack {
            trackIndex += 1
            guard trackIndex < sessionTracks.count else {
                completeSession()
                return
            }
            pending = [announcement(trackIndex), track(trackIndex)]
        } else {
            pending = [track(trackIndex)]
        }
        loadNext(autoplay: shouldPlay)
    }

    private func play() {
        guard !isPlaying, canPlay else { return }
        if completed { reset() }
        guard configureAudioSession() else { return }
        if let player {
            begin(player)
        } else if let speechText {
            speak(speechText)
        } else {
            sessionTracks = selectedTracks
            guard !sessionTracks.isEmpty else { return }
            record("Session started")
            pending = [announcement(0), track(0)]
            loadNext(autoplay: true)
        }
    }

    private func pause(_ message: String) {
        guard isPlaying else { return }
        player?.pause()
        speaker?.pauseSpeaking(at: .immediate)
        speechDeadline?.cancel()
        updateProgress()
        isPlaying = false
        stopTimer()
        record(message)
        publishNowPlaying()
    }

    private func announcement(_ index: Int) -> AudioSegment {
        let song = sessionTracks[index]
        return AudioSegment(kind: .announcement, title: "Introducing \(song.title)",
                            subtitle: song.artist.map { "Presenter · \($0)" } ?? "Presenter",
                            source: song.introduction)
    }

    private func track(_ index: Int) -> AudioSegment {
        let song = sessionTracks[index]
        return AudioSegment(kind: .track, title: song.title, subtitle: song.artist ?? "Imported track", source: song.source)
    }

    private var selectedTracks: [SessionTrack] {
        if mode == .demo { return Self.demoTracks }
        guard let playlist else { return [] }
        return playlist.tracks.map { track in
            let artist = track.artist.map { ", by \($0)" } ?? ""
            return SessionTrack(title: track.title, artist: track.artist, source: .file(playlist.audioURL(for: track)),
                                introduction: .speech("Up next, \(track.title)\(artist)."))
        }
    }

    private func setReadyDisplay() {
        demoTime = mode == .demo ? Self.startTime : .now
        currentTitle = "Ready to listen"
        currentSubtitle = mode == .demo ? "Start your sample listening session." : "Play your imported tracks in playlist order."
        currentKind = .idle
    }

    private func loadNext(autoplay: Bool) {
        while !pending.isEmpty {
            let segment = pending.removeFirst()
            if segment.kind == .news && !newsEnabled || segment.kind == .travel && !worksEnabled {
                continue
            }
            if case .speech(let text) = segment.source {
                prepareDisplay(for: segment)
                speechText = text
                if autoplay { speak(text) }
                else { publishNowPlaying() }
                return
            }
            guard let url = audioURL(for: segment.source),
                  let next = try? AVAudioPlayer(contentsOf: url), next.duration.isFinite, next.duration > 0 else {
                recordAssetError("Missing or invalid audio for \(segment.title).")
                if segment.kind == .track {
                    completeSession(failed: true)
                    return
                }
                continue
            }
            let identity = UUID()
            let completion = AudioCompletion { [weak self] success in
                Task { @MainActor [weak self] in self?.finished(identity, success: success) }
            }
            next.delegate = completion
            next.volume = mode == .demo ? Float(outputVolume) : 1
            next.prepareToPlay()
            delegate = completion
            playerID = identity
            player = next
            prepareDisplay(for: segment)
            duration = next.duration
            if autoplay {
                begin(next)
            } else {
                publishNowPlaying()
            }
            return
        }
        completeSession()
    }

    private func audioURL(for source: AudioSource) -> URL? {
        switch source {
        case .fixture(let name):
            bundle.url(forResource: name, withExtension: "wav", subdirectory: "Audio")
                ?? bundle.url(forResource: name, withExtension: "wav")
        case .file(let url): url
        case .speech: nil
        }
    }

    private func prepareDisplay(for segment: AudioSegment) {
        currentKind = segment.kind
        currentTitle = segment.title
        currentSubtitle = segment.subtitle
        audioStart = demoTime
    }

    private func speak(_ text: String) {
        if let speaker, let identity = playerID, speaker.isPaused, speaker.continueSpeaking() {
            isPlaying = true
            record("Resumed \(currentTitle)")
            watchSpeech(identity)
            publishNowPlaying()
            return
        }
        speaker?.delegate = nil
        speaker?.stopSpeaking(at: .immediate)
        let identity = UUID()
        playerID = identity
        let synthesizer = AVSpeechSynthesizer()
        let completion = SpeechCompletion { [weak self] success in
            Task { @MainActor [weak self] in self?.finished(identity, success: success) }
        }
        speechDelegate = completion
        synthesizer.delegate = completion
        #if os(iOS)
        synthesizer.usesApplicationAudioSession = true
        #endif
        speaker = synthesizer
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        isPlaying = true
        record("Playing \(currentTitle)")
        synthesizer.speak(utterance)
        watchSpeech(identity)
        publishNowPlaying()
    }

    private func watchSpeech(_ identity: UUID) {
        speechDeadline?.cancel()
        speechDeadline = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.finished(identity, success: false)
        }
    }

    private func begin(_ source: AVAudioPlayer) {
        let currentTime = source.currentTime
        guard source.play() else {
            recordAssetError(Self.outputError)
            releaseAudioSession()
            publishNowPlaying()
            return
        }
        if assetError == Self.outputError { assetError = nil }
        isPlaying = true
        record(currentTime == 0 ? "Playing \(currentTitle)" : "Resumed \(currentTitle)")
        startTimer()
        publishNowPlaying()
    }

    private func finished(_ identity: UUID, success: Bool) {
        guard playerID == identity, isPlaying, player?.isPlaying != true else { return }
        let wasTrack = currentKind == .track
        if success {
            if mode == .demo { demoTime = audioStart.addingTimeInterval(duration) }
            record("Finished \(currentTitle)")
        } else {
            recordAssetError("Playback failed for \(currentTitle).")
        }
        discardPlayer()

        if wasTrack {
            if !success {
                completeSession(failed: true)
                return
            }
            let nextIndex = trackIndex + 1
            guard nextIndex < sessionTracks.count else {
                completeSession()
                return
            }
            pending = mode == .demo ? segmentsAtBoundary(after: trackIndex) : []
            trackIndex = nextIndex
            pending += [announcement(nextIndex), track(nextIndex)]
        }
        loadNext(autoplay: true)
    }

    private func segmentsAtBoundary(after index: Int) -> [AudioSegment] {
        let minutes = scenario == .expired ? 16 + 4 * index : 1 + 4 * index
        demoTime = max(demoTime, Self.bulletinHour.addingTimeInterval(Double(minutes * 60)))
        var segments: [AudioSegment] = []

        if newsEnabled && !handledNews {
            let expiry = Self.bulletinHour.addingTimeInterval(15 * 60)
            let available = Self.bulletinHour.addingTimeInterval(scenario == .lateNews ? 2 * 60 : 30)
            if demoTime >= expiry {
                handledNews = true
                record("Hourly bulletin expired")
            } else if demoTime >= available {
                handledNews = true
                segments.append(AudioSegment(kind: .news, title: "Hourly news bulletin",
                                             subtitle: "Sample bulletin · 10:00 edition", source: .fixture("news")))
                record("Fresh bulletin queued at song boundary")
            } else if !loggedLateNews {
                loggedLateNews = true
                record("Bulletin still loading. Music continues.")
            }
        }

        if worksEnabled && !handledTravel {
            handledTravel = true
            let update = Self.bulletinHour.addingTimeInterval(30)
            if scenario == .reopened {
                record("Road reopened. Previous closure suppressed.")
            } else if demoTime.timeIntervalSince(update) >= 5 * 60 {
                record("Travel report expired")
            } else {
                segments.append(AudioSegment(kind: .travel, title: "Cornwall roadworks",
                                             subtitle: "Sample report · Lantern Cove", source: .fixture("travel")))
                record("Fresh roadworks report queued")
            }
        }
        return segments
    }

    private func completeSession(failed: Bool = false) {
        discardPlayer()
        releaseAudioSession()
        completed = true
        currentKind = .idle
        currentTitle = failed ? "Playback stopped" : "Session complete"
        currentSubtitle = failed ? "Check the audio file, then try again." : "Press Play to listen again."
        record(failed ? "Session stopped on an audio error" : "Session finished")
        publishNowPlaying()
    }

    private func discardPlayer() {
        playerID = nil
        player?.delegate = nil
        player?.stop()
        player = nil
        delegate = nil
        speaker?.delegate = nil
        speaker?.stopSpeaking(at: .immediate)
        speaker = nil
        speechDelegate = nil
        speechText = nil
        speechDeadline?.cancel()
        speechDeadline = nil
        stopTimer()
        isPlaying = false
        elapsed = 0
        duration = 0
    }

    private func recordAssetError(_ message: String) {
        assetError = message
        record(message)
    }

    private func record(_ message: String) {
        if phaseLog.count == 40 { phaseLog.removeFirst() }
        phaseLog.append(PlaybackEvent(time: mode == .demo ? demoTime : .now, message: message))
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated { self.updateProgress() }
        }
        progressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let player else { return }
        let time = player.currentTime
        // Some outputs reset currentTime to zero as they deliver the end event.
        guard time > 0 || elapsed == 0 else { return }
        elapsed = time
        demoTime = audioStart.addingTimeInterval(elapsed)
    }

    private func configureAudioSession() -> Bool {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
            hasActiveAudioSession = true
            if assetError == Self.sessionError { assetError = nil }
        } catch {
            recordAssetError(Self.sessionError)
            return false
        }
        #endif
        return true
    }

    private func releaseAudioSession() {
        #if os(iOS)
        guard hasActiveAudioSession else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            hasActiveAudioSession = false
        } catch {
            record("Could not release the audio session.")
        }
        #endif
    }

    private func publishNowPlaying() {
        #if os(iOS)
        let centre = MPNowPlayingInfoCenter.default()
        centre.nowPlayingInfo = currentKind == .idle ? nil : [
            MPMediaItemPropertyTitle: currentTitle,
            MPMediaItemPropertyArtist: currentSubtitle,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        #endif
    }

    #if os(iOS)
    private func registerSystemControls() {
        let controls = MPRemoteCommandCenter.shared()
        bind(controls.playCommand) { $0.play() }
        bind(controls.pauseCommand) { $0.pause("Paused from Now Playing") }
        bind(controls.togglePlayPauseCommand) { $0.togglePlayback() }
        bind(controls.nextTrackCommand) { $0.skip() }

        let notifications = NotificationCenter.default
        notifications.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                || raw == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue {
                Task { @MainActor [weak self] in self?.stopForRouteChange() }
            }
        }
        notifications.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor [weak self] in self?.pause("Audio interrupted. Press Play to continue.") }
            }
        }
    }

    private func bind(_ command: MPRemoteCommand, to action: @escaping @MainActor @Sendable (PlaybackModel) -> Void) {
        command.addTarget { [weak self] _ in
            guard let self else { return .noActionableNowPlayingItem }
            Task { @MainActor in action(self) }
            return .success
        }
    }
    #endif
}
