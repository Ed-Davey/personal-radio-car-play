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

struct PlaybackEvent: Identifiable {
    let id = UUID()
    let time: Date
    let message: String
}

private struct AudioSegment {
    let kind: PlaybackKind
    let title: String
    let subtitle: String
    let filename: String
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

@MainActor @Observable final class PlaybackModel {
    private static let tracks = [
        (title: "Harbour Lights", artist: "The Breakwater Club"),
        (title: "Low Tide", artist: "Sundown Parcel"),
        (title: "Headland Air", artist: "North Marker")
    ]

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
    var progress: Double { duration > 0 ? min(1, elapsed / duration) : 0 }
    var upcoming: [String] {
        if currentKind == .idle {
            return completed ? [] : Self.tracks.map(\.title)
        }
        if currentKind == .track {
            return Self.tracks.dropFirst(trackIndex + 1).map(\.title)
        }
        return pending.filter { $0.kind == .news || $0.kind == .travel }.map(\.title)
            + Self.tracks.dropFirst(trackIndex).map(\.title)
    }

    @ObservationIgnored private let bundle: Bundle
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var audioStart = PlaybackModel.startTime
    @ObservationIgnored private var playerID: UUID?
    @ObservationIgnored private var delegate: AudioCompletion?
    private var trackIndex = 0
    private var pending: [AudioSegment] = []
    private var handledNews = false
    private var handledTravel = false
    private var loggedLateNews = false
    private var completed = false

    init(resourceBundle: Bundle = .main) {
        bundle = resourceBundle
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

    func reset() {
        discardPlayer()
        pending = []
        trackIndex = 0
        handledNews = false
        handledTravel = false
        loggedLateNews = false
        completed = false
        assetError = nil
        demoTime = Self.startTime
        phaseLog = []
        currentTitle = "Ready to listen"
        currentSubtitle = "Start your sample listening session."
        currentKind = .idle
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
            guard trackIndex < Self.tracks.count else {
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
        guard !isPlaying else { return }
        guard configureAudioSession() else { return }
        if let player {
            begin(player)
        } else {
            if completed || currentKind != .idle { reset() }
            record("Session started")
            pending = [announcement(0), track(0)]
            loadNext(autoplay: true)
        }
    }

    private func pause(_ message: String) {
        guard let player, isPlaying else { return }
        player.pause()
        updateProgress()
        isPlaying = false
        stopTimer()
        record(message)
        publishNowPlaying()
    }

    private func announcement(_ index: Int) -> AudioSegment {
        let song = Self.tracks[index]
        return AudioSegment(kind: .announcement, title: "Introducing \(song.title)",
                            subtitle: "Presenter · \(song.artist)", filename: "intro-\(index + 1)")
    }

    private func track(_ index: Int) -> AudioSegment {
        let song = Self.tracks[index]
        return AudioSegment(kind: .track, title: song.title, subtitle: song.artist, filename: "track-\(index + 1)")
    }

    private func loadNext(autoplay: Bool) {
        while !pending.isEmpty {
            let segment = pending.removeFirst()
            if segment.kind == .news && !newsEnabled || segment.kind == .travel && !worksEnabled {
                continue
            }
            guard let url = bundle.url(forResource: segment.filename, withExtension: "wav", subdirectory: "Audio")
                ?? bundle.url(forResource: segment.filename, withExtension: "wav"),
                  let next = try? AVAudioPlayer(contentsOf: url), next.duration > 0 else {
                recordAssetError("Missing or invalid audio for \(segment.title).")
                if segment.kind == .track { break }
                continue
            }
            let identity = UUID()
            let completion = AudioCompletion { [weak self] success in
                Task { @MainActor [weak self] in self?.finished(identity, success: success) }
            }
            next.delegate = completion
            next.volume = Float(outputVolume)
            next.prepareToPlay()
            delegate = completion
            playerID = identity
            player = next
            currentKind = segment.kind
            currentTitle = segment.title
            currentSubtitle = segment.subtitle
            duration = next.duration
            audioStart = demoTime
            if autoplay {
                begin(next)
            } else {
                publishNowPlaying()
            }
            return
        }
        completeSession()
    }

    private func begin(_ source: AVAudioPlayer) {
        let currentTime = source.currentTime
        guard source.play() else {
            recordAssetError("Audio output could not start. Check the output and press Play to retry.")
            publishNowPlaying()
            return
        }
        assetError = nil
        isPlaying = true
        record(currentTime == 0 ? "Playing \(currentTitle)" : "Resumed \(currentTitle)")
        startTimer()
        publishNowPlaying()
    }

    private func finished(_ identity: UUID, success: Bool) {
        guard let player, playerID == identity, isPlaying, !player.isPlaying else { return }
        let wasTrack = currentKind == .track
        if success {
            demoTime = audioStart.addingTimeInterval(duration)
            record("Finished \(currentTitle)")
        } else {
            recordAssetError("Playback failed for \(currentTitle).")
        }
        discardPlayer()

        if wasTrack {
            // An unsuccessful song is never treated as a bulletin boundary.
            let nextIndex = trackIndex + 1
            guard nextIndex < Self.tracks.count else {
                completeSession()
                return
            }
            pending = success ? segmentsAtBoundary(after: trackIndex) : []
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
                                             subtitle: "Sample bulletin · 10:00 edition", filename: "news"))
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
                                             subtitle: "Sample report · Lantern Cove", filename: "travel"))
                record("Fresh roadworks report queued")
            }
        }
        return segments
    }

    private func completeSession() {
        discardPlayer()
        completed = true
        currentKind = .idle
        currentTitle = "Session complete"
        currentSubtitle = "Press Play to listen again."
        record("Session finished")
        publishNowPlaying()
    }

    private func discardPlayer() {
        playerID = nil
        player?.delegate = nil
        player?.stop()
        player = nil
        delegate = nil
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
        phaseLog.append(PlaybackEvent(time: demoTime, message: message))
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
        } catch {
            recordAssetError("Audio session unavailable. Press Play to try again.")
            return false
        }
        #endif
        return true
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
