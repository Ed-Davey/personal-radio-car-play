import Foundation
import Testing
@testable import PersonalRadioCore

@Suite("Local playlist integration")
@MainActor
struct PlaylistIntegrationTests {
    @Test("A playable WAV is copied with its duration and fallback title")
    func importPersistsPrivateCopy() async throws {
        let fixture = try TestAudioFixture()
        defer { fixture.cleanUp() }
        let source = try fixture.makeWAV("  Cove  track .WAV", frames: 1_600)
        let originalAudio = try Data(contentsOf: source)
        let playlist = try LocalPlaylist(directory: fixture.playlistDirectory)

        let imported = try await playlist.importTracks(from: [source])
        let track = try #require(imported.first)
        #expect(imported.count == 1)
        #expect(track.title == "Cove track")
        #expect(track.artist == nil)
        #expect(abs(track.duration - 0.2) < 0.001)
        #expect(playlist.tracks == imported)
        #expect(playlist.audioURL(for: track) != source)
        #expect(try Data(contentsOf: playlist.audioURL(for: track)) == originalAudio)
        try FileManager.default.removeItem(at: source)

        let reopened = try LocalPlaylist(directory: fixture.playlistDirectory)
        #expect(reopened.tracks == imported)
        #expect(try Data(contentsOf: reopened.audioURL(for: track)) == originalAudio)
    }

    @Test("Reordering and removing tracks persists the intended IDs and files")
    func reorderAndRemove() async throws {
        let fixture = try TestAudioFixture()
        defer { fixture.cleanUp() }
        let sources = try ["One.wav", "Two.wav", "Three.wav"].map { try fixture.makeWAV($0) }
        let playlist = try LocalPlaylist(directory: fixture.playlistDirectory)
        let tracks = try await playlist.importTracks(from: sources)
        try #require(tracks.count == 3)
        let removedCopy = playlist.audioURL(for: tracks[0])

        try playlist.move(from: IndexSet([0, 2]), to: 3)
        let reordered = try LocalPlaylist(directory: fixture.playlistDirectory)
        #expect(reordered.tracks == [tracks[1], tracks[0], tracks[2]])

        try reordered.remove(at: IndexSet(integer: 1))
        let reopened = try LocalPlaylist(directory: fixture.playlistDirectory)
        #expect(reopened.tracks == [tracks[1], tracks[2]])
        #expect(!FileManager.default.fileExists(atPath: removedCopy.path))
        #expect(sources.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(reopened.tracks.allSatisfy {
            FileManager.default.fileExists(atPath: reopened.audioURL(for: $0).path)
        })
    }

    @Test("A corrupt file rolls back the whole batch and clears staging")
    func batchRollback() async throws {
        let fixture = try TestAudioFixture()
        defer { fixture.cleanUp() }
        let saved = try fixture.makeWAV("Keep.wav")
        let newTrack = try fixture.makeWAV("Would import.wav")
        let damaged = try fixture.makeFile("Damaged.wav", contents: Data("invalid audio".utf8))
        let playlist = try LocalPlaylist(directory: fixture.playlistDirectory)
        let initialTracks = try await playlist.importTracks(from: [saved])
        let initialTrack = try #require(initialTracks.first)
        let audioDirectory = playlist.audioURL(for: initialTrack).deletingLastPathComponent()
        let initialFiles = try FileManager.default.contentsOfDirectory(atPath: audioDirectory.path)
        let manifestURL = fixture.playlistDirectory.appendingPathComponent("playlist.json")
        let initialManifest = try Data(contentsOf: manifestURL)

        do {
            try await playlist.importTracks(from: [newTrack, damaged])
            Issue.record("A batch with damaged audio unexpectedly succeeded.")
        } catch LocalPlaylistError.unreadableFile(let title) {
            #expect(title == "Damaged")
        }

        #expect(!playlist.isImporting)
        #expect(playlist.tracks == initialTracks)
        #expect(try Data(contentsOf: manifestURL) == initialManifest)
        #expect(try FileManager.default.contentsOfDirectory(atPath: audioDirectory.path) == initialFiles)
        let entries = try FileManager.default.contentsOfDirectory(atPath: fixture.playlistDirectory.path)
        #expect(!entries.contains { $0.hasPrefix(".import-") })
        let reopened = try LocalPlaylist(directory: fixture.playlistDirectory)
        #expect(reopened.tracks == initialTracks)
    }

    @Test("Unsupported and oversized files leave the playlist empty")
    func rejectsUnsupportedAndOversizedImports() async throws {
        let fixture = try TestAudioFixture()
        defer { fixture.cleanUp() }
        let unsupported = try fixture.makeWAV("Unsupported.ogg")
        let oversized = try fixture.makeFile("Oversized.wav", contents: Data())
        let handle = try FileHandle(forWritingTo: oversized)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 100_000_001)
        let playlist = try LocalPlaylist(directory: fixture.playlistDirectory)

        do {
            try await playlist.importTracks(from: [unsupported])
            Issue.record("An unsupported extension was accepted.")
        } catch LocalPlaylistError.unsupportedFile(let title) {
            #expect(title == "Unsupported")
        }

        do {
            try await playlist.importTracks(from: [oversized])
            Issue.record("An oversized file was accepted.")
        } catch LocalPlaylistError.fileTooLarge(let title) {
            #expect(title == "Oversized")
        }

        #expect(playlist.tracks.isEmpty)
        #expect(!playlist.isImporting)
        let entries = try FileManager.default.contentsOfDirectory(atPath: fixture.playlistDirectory.path)
        #expect(!entries.contains { $0.hasPrefix(".import-") })
        let reopened = try LocalPlaylist(directory: fixture.playlistDirectory)
        #expect(reopened.tracks.isEmpty)
    }

    @Test("A stale library cannot overwrite another instance's edited playlist")
    func rejectsStaleEdit() async throws {
        let fixture = try TestAudioFixture()
        defer { fixture.cleanUp() }
        let first = try fixture.makeWAV("First.wav")
        let second = try fixture.makeWAV("Second.wav")
        let writer = try LocalPlaylist(directory: fixture.playlistDirectory)
        let tracks = try await writer.importTracks(from: [first, second])
        let stale = try LocalPlaylist(directory: fixture.playlistDirectory)

        try writer.move(from: IndexSet(integer: 0), to: 2)
        do {
            try stale.remove(at: IndexSet(integer: 0))
            Issue.record("A stale library overwrote a concurrent edit.")
        } catch LocalPlaylistError.playlistChanged {
            #expect(stale.tracks == tracks)
        }

        let reopened = try LocalPlaylist(directory: fixture.playlistDirectory)
        #expect(reopened.tracks == Array(tracks.reversed()))
    }
}
