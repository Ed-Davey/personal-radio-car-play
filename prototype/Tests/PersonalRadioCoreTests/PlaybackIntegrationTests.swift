import AVFoundation
import Foundation
import Testing
@testable import PersonalRadioCore

@MainActor
struct PlaybackIntegrationTests {
    @Test("Natural song endings play the reports before the next introduction")
    func naturalSongBoundaries() async throws {
        let harness = try PlaybackHarness()
        defer { harness.cleanUp() }
        let model = harness.model
        model.togglePlayback()

        #expect(model.currentKind == .announcement)
        #expect(model.currentTitle == "Introducing Harbour Lights")
        try await harness.finishCurrent(expecting: .track, title: "Harbour Lights")
        try await harness.finishCurrent(expecting: .news, title: "Hourly news bulletin")
        #expect(model.upcoming == ["Cornwall roadworks", "Low Tide", "Headland Air"])
        try await harness.finishCurrent(expecting: .travel, title: "Cornwall roadworks")
        try await harness.finishCurrent(expecting: .announcement, title: "Introducing Low Tide")
        try await harness.finishCurrent(expecting: .track, title: "Low Tide")
        try await harness.finishCurrent(expecting: .announcement, title: "Introducing Headland Air")
        try await harness.finishCurrent(expecting: .track, title: "Headland Air")
        try await harness.finishCurrent(expecting: .idle, title: "Session complete")

        #expect(!model.isPlaying)
        #expect(model.upcoming.isEmpty)
        #expect(model.assetError == nil)
    }

    @Test("Manual skips advance without making the skipped song a natural boundary")
    func manualSkips() async throws {
        let harness = try PlaybackHarness()
        defer { harness.cleanUp() }
        let model = harness.model
        model.togglePlayback()

        model.skip()
        #expect(model.currentTitle == "Harbour Lights")
        model.skip()
        #expect(model.currentTitle == "Introducing Low Tide")
        #expect(model.upcoming == ["Low Tide", "Headland Air"])
        try await harness.finishCurrent(expecting: .track, title: "Low Tide")
        try await harness.finishCurrent(expecting: .news, title: "Hourly news bulletin")

        model.skip()
        #expect(model.currentKind == .track)
        #expect(model.currentTitle == "Headland Air")
        #expect(model.isPlaying)
    }

    @Test("A route change holds playback until the listener presses Play")
    func routeChangeHoldsPlayback() async throws {
        let harness = try PlaybackHarness()
        defer { harness.cleanUp() }
        let model = harness.model
        model.togglePlayback()
        let introducing = try #require(harness.players.current)

        model.stopForRouteChange()
        #expect(model.isPaused)
        #expect(!introducing.isPlaying)
        introducing.finish()
        await Task { @MainActor in }.value
        #expect(model.currentTitle == "Introducing Harbour Lights")
        #expect(model.isPaused)

        model.skip()
        #expect(model.currentTitle == "Harbour Lights")
        #expect(model.isPaused)
        model.togglePlayback()
        #expect(model.isPlaying)
        #expect(model.currentTitle == "Harbour Lights")
    }

    @Test("A completion from an abandoned player cannot stop the active track")
    func ignoresStaleCompletions() async throws {
        let harness = try PlaybackHarness()
        defer { harness.cleanUp() }
        let model = harness.model
        model.togglePlayback()
        let abandoned = try #require(harness.players.current)
        let abandonedDelegate = try #require(abandoned.delegate)
        model.skip()
        let active = try #require(harness.players.current)

        // This simulates the active file ending before its own callback is delivered.
        active.pause()
        abandoned.finish(success: false, through: abandonedDelegate)
        await Task { @MainActor in }.value

        #expect(model.currentTitle == "Harbour Lights")
        #expect(model.isPlaying)
        #expect(model.assetError == nil)
        try await harness.finishCurrent(expecting: .news, title: "Hourly news bulletin")
    }

    @Test("An output failure can be retried, and a track decode failure stops playback")
    func outputAndDecodeFailures() async throws {
        let harness = try PlaybackHarness()
        defer { harness.cleanUp() }
        let model = harness.model
        harness.players.acceptsPlay = false
        model.togglePlayback()

        #expect(model.isPaused)
        #expect(model.assetError?.contains("Audio output could not start") == true)
        let pausedPlayer = try #require(harness.players.current)
        pausedPlayer.acceptsPlay = true
        harness.players.acceptsPlay = true
        model.togglePlayback()
        #expect(model.isPlaying)
        #expect(model.assetError == nil)
        try await harness.finishCurrent(expecting: .track, title: "Harbour Lights")

        let track = try #require(harness.players.current)
        track.failDecoding()
        try await harness.waitForPlayback(.idle, title: "Playback stopped")
        #expect(!model.isPlaying)
        #expect(model.assetError == "Playback failed for Harbour Lights.")
        #expect(model.upcoming.isEmpty)
    }

    @Test("Disabling a queued report removes it from the upcoming items and playback")
    func disablesQueuedReport() async throws {
        let harness = try PlaybackHarness()
        defer { harness.cleanUp() }
        let model = harness.model
        model.togglePlayback()
        try await harness.finishCurrent(expecting: .track, title: "Harbour Lights")
        try await harness.finishCurrent(expecting: .news, title: "Hourly news bulletin")
        #expect(model.upcoming.first == "Cornwall roadworks")

        model.worksEnabled = false
        #expect(model.upcoming == ["Low Tide", "Headland Air"])
        try await harness.finishCurrent(expecting: .announcement, title: "Introducing Low Tide")
    }
}

@MainActor
private struct PlaybackHarness {
    let model: PlaybackModel
    let players: ControlledPlayerFactory
    private let fixture: TestAudioFixture

    init() throws {
        let fixture = try TestAudioFixture()
        do {
            let bundleURL = fixture.directory.appendingPathComponent("PlaybackFixtures.bundle")
            let contents = bundleURL.appendingPathComponent("Contents")
            let audio = contents.appendingPathComponent("Resources/Audio")
            try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
            let plist = try PropertyListSerialization.data(
                fromPropertyList: [
                    "CFBundleIdentifier": "com.personalradio.tests.playback",
                    "CFBundlePackageType": "BNDL"
                ],
                format: .xml,
                options: 0
            )
            try plist.write(to: contents.appendingPathComponent("Info.plist"))
            let sample = try fixture.makeWAV("fixture.wav")
            for name in ["intro-1", "intro-2", "intro-3", "track-1", "track-2", "track-3", "news", "travel"] {
                try FileManager.default.copyItem(at: sample, to: audio.appendingPathComponent("\(name).wav"))
            }

            let bundle = try #require(Bundle(url: bundleURL))
            let players = ControlledPlayerFactory()
            self.fixture = fixture
            self.players = players
            model = PlaybackModel(
                resourceBundle: bundle,
                playlistDirectory: fixture.playlistDirectory,
                makePlayer: players.makePlayer
            )
        } catch {
            fixture.cleanUp()
            throw error
        }
    }

    func finishCurrent(expecting kind: PlaybackKind, title: String) async throws {
        try #require(players.current).finish()
        try await waitForPlayback(kind, title: title)
    }

    func waitForPlayback(_ kind: PlaybackKind, title: String) async throws {
        // The AVAudioPlayer delegate hops to the main actor. Yield to its task.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while (model.currentKind != kind || model.currentTitle != title) && ContinuousClock.now < deadline {
            await Task.yield()
        }
        try #require(model.currentKind == kind)
        try #require(model.currentTitle == title)
    }

    func cleanUp() {
        model.reset()
        fixture.cleanUp()
    }
}

@MainActor
private final class ControlledPlayerFactory {
    var acceptsPlay = true
    private(set) var current: ControlledAudioPlayer?

    func makePlayer(_ url: URL) throws -> AVAudioPlayer {
        let player = try ControlledAudioPlayer(contentsOf: url)
        player.acceptsPlay = acceptsPlay
        current = player
        return player
    }
}

private final class ControlledAudioPlayer: AVAudioPlayer {
    var acceptsPlay = true
    private var active = false

    override var isPlaying: Bool { active }

    override func prepareToPlay() -> Bool { true }

    override func play() -> Bool {
        active = acceptsPlay
        return active
    }

    override func pause() { active = false }
    override func stop() { active = false }

    func finish(success: Bool = true, through receiver: (any AVAudioPlayerDelegate)? = nil) {
        active = false
        (receiver ?? delegate)?.audioPlayerDidFinishPlaying?(self, successfully: success)
    }

    func failDecoding() {
        active = false
        delegate?.audioPlayerDecodeErrorDidOccur?(self, error: CocoaError(.fileReadCorruptFile))
    }
}
