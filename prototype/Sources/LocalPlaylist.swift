import AVFoundation
import Foundation
import Observation

private enum AudioFileFormat: String, Codable, Sendable {
    case aif, aiff, m4a, mp3, wav
}

struct LocalTrack: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let artist: String?
    let duration: TimeInterval
    fileprivate let format: AudioFileFormat
    fileprivate let byteCount: Int64

    fileprivate var filename: String { id.uuidString + "." + format.rawValue }
}

enum LocalPlaylistError: LocalizedError {
    case busy
    case tooManyTracks
    case unsupportedFile(String)
    case unreadableFile(String)
    case protectedFile(String)
    case fileTooLarge(String)
    case libraryTooLarge
    case invalidManifest
    case invalidSelection
    case playlistChanged

    var errorDescription: String? {
        switch self {
        case .busy: "Wait for the current playlist operation to finish."
        case .tooManyTracks: "The pilot playlist can hold up to 100 tracks."
        case .unsupportedFile(let title): "Use a DRM-free MP3, M4A, WAV or AIFF file for \(title)."
        case .unreadableFile(let title): "Could not read a playable audio track from \(title)."
        case .protectedFile(let title): "\(title) is protected and cannot be imported."
        case .fileTooLarge(let title): "\(title) is larger than the 100 MB per-track limit."
        case .libraryTooLarge: "The pilot playlist can store up to 2 GB of audio."
        case .invalidManifest: "The saved playlist could not be read. Its files have been kept."
        case .invalidSelection: "That playlist selection is no longer available."
        case .playlistChanged: "Another session changed the playlist. Reopen it before making changes."
        }
    }
}

@MainActor @Observable
final class LocalPlaylist {
    nonisolated private static let maxTracks = 100
    nonisolated private static let maxFileBytes: Int64 = 100_000_000
    nonisolated private static let maxPlaylistBytes: Int64 = 2_000_000_000
    nonisolated private static let manifestVersion = 1

    private struct Manifest: Codable {
        let version: Int
        let tracks: [LocalTrack]
    }

    private(set) var tracks: [LocalTrack] = []
    private(set) var isImporting = false

    private let directory: URL
    private let audioDirectory: URL
    private let manifestURL: URL
    private let lockURL: URL

    init(directory: URL? = nil) throws {
        let manager = FileManager.default
        let root = try directory ?? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Personal Radio", isDirectory: true)
            .appendingPathComponent("Local Playlist", isDirectory: true)
        self.directory = root.standardizedFileURL
        audioDirectory = self.directory.appendingPathComponent("Audio", isDirectory: true)
        manifestURL = self.directory.appendingPathComponent("playlist.json")
        lockURL = self.directory.appendingPathComponent(".playlist.lock")
        try manager.createDirectory(at: audioDirectory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        tracks = try Self.withLock(at: lockURL) {
            let saved = try Self.readManifest(at: manifestURL)
            pruneUnreferencedAudio(keeping: saved)
            pruneInterruptedImports()
            return saved
        }
    }

    func audioURL(for track: LocalTrack) -> URL {
        audioDirectory.appendingPathComponent(track.filename, isDirectory: false)
    }

    @discardableResult
    func importTracks(from urls: [URL]) async throws -> [LocalTrack] {
        guard !urls.isEmpty else { return [] }
        guard !isImporting else { throw LocalPlaylistError.busy }
        guard urls.count <= Self.maxTracks - tracks.count else { throw LocalPlaylistError.tooManyTracks }

        let manager = FileManager.default
        let staging = directory.appendingPathComponent(".import-" + UUID().uuidString, isDirectory: true)
        let lease = try Self.withLock(at: lockURL) {
            try manager.createDirectory(at: staging, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            do {
                return try Self.acquireLock(at: staging.appendingPathComponent(".lease"))
            } catch {
                try? manager.removeItem(at: staging)
                throw error
            }
        }
        isImporting = true
        defer {
            try? manager.removeItem(at: staging)
            close(lease)
            isImporting = false
        }

        let storedBytes = tracks.reduce(Int64(0)) { $0 + $1.byteCount }
        let importTask = Task.detached(priority: .userInitiated) {
            try await Self.prepareTracks(urls, in: staging, storedBytes: storedBytes)
        }
        let imported = try await withTaskCancellationHandler {
            try await importTask.value
        } onCancel: {
            importTask.cancel()
        }
        try Task.checkCancellation()
        try replaceTracks(with: tracks + imported, installing: imported, from: staging)
        return imported
    }

    func remove(at offsets: IndexSet) throws {
        try validate(offsets)
        guard !offsets.isEmpty else { return }
        let remaining = tracks.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        try replaceTracks(with: remaining)
    }

    func move(from offsets: IndexSet, to destination: Int) throws {
        try validate(offsets)
        guard (0...tracks.count).contains(destination) else { throw LocalPlaylistError.invalidSelection }
        guard !offsets.isEmpty else { return }
        let selection = offsets.map { tracks[$0] }
        var reordered = tracks.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let precedingRemoved = offsets.prefix(while: { $0 < destination }).count
        reordered.insert(contentsOf: selection, at: destination - precedingRemoved)
        if tracks != reordered { try replaceTracks(with: reordered) }
    }

    func clear() throws {
        guard !isImporting else { throw LocalPlaylistError.busy }
        guard !tracks.isEmpty else { return }
        try replaceTracks(with: [])
    }

    private func validate(_ offsets: IndexSet) throws {
        guard !isImporting else { throw LocalPlaylistError.busy }
        if let last = offsets.last, !tracks.indices.contains(last) {
            throw LocalPlaylistError.invalidSelection
        }
    }

    private func replaceTracks(
        with replacement: [LocalTrack], installing imported: [LocalTrack] = [], from staging: URL? = nil
    ) throws {
        try Self.withLock(at: lockURL) {
            guard try Self.readManifest(at: manifestURL) == tracks else {
                throw LocalPlaylistError.playlistChanged
            }
            let manager = FileManager.default
            var installed: [URL] = []
            do {
                if let staging {
                    for track in imported {
                        let destination = audioURL(for: track)
                        try manager.moveItem(at: staging.appendingPathComponent(track.filename), to: destination)
                        installed.append(destination)
                    }
                }
                let manifest = Manifest(version: Self.manifestVersion, tracks: replacement)
                try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
            } catch {
                for url in installed { try? manager.removeItem(at: url) }
                throw error
            }
            tracks = replacement
            pruneUnreferencedAudio(keeping: replacement)
        }
    }

    private func pruneUnreferencedAudio(keeping tracks: [LocalTrack]) {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: audioDirectory,
                                                            includingPropertiesForKeys: nil) else { return }
        let keep = Set(tracks.map(\.filename))
        for file in files where !keep.contains(file.lastPathComponent) {
            let basename = file.deletingPathExtension().lastPathComponent
            if UUID(uuidString: basename) != nil, AudioFileFormat(rawValue: file.pathExtension) != nil {
                try? manager.removeItem(at: file)
            }
        }
    }

    // App termination can leave an uncommitted import behind. A live importer still
    // owns its lease, including when a second app instance opens the same library.
    private func pruneInterruptedImports() {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let files = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else {
            return
        }
        for file in files where file.lastPathComponent.hasPrefix(".import-") {
            let suffix = String(file.lastPathComponent.dropFirst(".import-".count))
            guard UUID(uuidString: suffix) != nil,
                  let values = try? file.resourceValues(forKeys: keys),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let lease = try? Self.acquireLock(at: file.appendingPathComponent(".lease")) else { continue }
            try? manager.removeItem(at: file)
            close(lease)
        }
    }

    private static func readManifest(at url: URL) throws -> [LocalTrack] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let attributes = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let bytes = attributes.fileSize, bytes <= 512_000 else { throw LocalPlaylistError.invalidManifest }
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
            let tracks = manifest.tracks
            guard manifest.version == manifestVersion, tracks.count <= maxTracks,
                  Set(tracks.map(\.id)).count == tracks.count,
                  tracks.allSatisfy({ $0.duration.isFinite && $0.duration > 0 &&
                      (1...maxFileBytes).contains($0.byteCount) &&
                      clean($0.title) == $0.title && clean($0.artist) == $0.artist }),
                  tracks.reduce(Int64(0), { $0 + $1.byteCount }) <= maxPlaylistBytes else {
                throw LocalPlaylistError.invalidManifest
            }
            return tracks
        } catch {
            throw LocalPlaylistError.invalidManifest
        }
    }

    private static func withLock<Result>(at url: URL, _ operation: () throws -> Result) throws -> Result {
        let descriptor = try acquireLock(at: url)
        defer { close(descriptor) }
        return try operation()
    }

    private static func acquireLock(at url: URL) throws -> Int32 {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let error = errno
            close(descriptor)
            if error == EWOULDBLOCK { throw LocalPlaylistError.busy }
            throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
        }
        return descriptor
    }

    nonisolated private static func prepareTracks(
        _ urls: [URL], in staging: URL, storedBytes: Int64
    ) async throws -> [LocalTrack] {
        var imported: [LocalTrack] = []
        var total = storedBytes
        for source in urls {
            try Task.checkCancellation()
            let filenameTitle = clean(source.deletingPathExtension().lastPathComponent) ?? "Untitled Track"
            guard let format = AudioFileFormat(rawValue: source.pathExtension.lowercased()) else {
                throw LocalPlaylistError.unsupportedFile(filenameTitle)
            }
            let id = UUID()
            let destination = staging.appendingPathComponent(id.uuidString + "." + format.rawValue)
            let remainingBytes = maxPlaylistBytes - total
            let bytes = try copyAudio(source, to: destination, title: filenameTitle, remainingBytes: remainingBytes)
            let asset = AVURLAsset(url: destination)
            let duration: TimeInterval
            do {
                let (playable, protected, time) = try await asset.load(.isPlayable, .hasProtectedContent, .duration)
                if protected { throw LocalPlaylistError.protectedFile(filenameTitle) }
                duration = time.seconds
                guard playable, duration.isFinite, duration > 0,
                      try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
                    throw LocalPlaylistError.unreadableFile(filenameTitle)
                }
            } catch let error as LocalPlaylistError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw LocalPlaylistError.unreadableFile(filenameTitle)
            }
            let metadata = (try? await asset.load(.commonMetadata)) ?? []
            let title = await metadataText(metadata, identifier: .commonIdentifierTitle) ?? filenameTitle
            let artist = await metadataText(metadata, identifier: .commonIdentifierArtist)
            imported.append(LocalTrack(id: id, title: title, artist: artist, duration: duration,
                                       format: format, byteCount: bytes))
            total += bytes
        }
        return imported
    }

    nonisolated private static func copyAudio(
        _ source: URL, to destination: URL, title: String, remainingBytes: Int64
    ) throws -> Int64 {
        guard source.isFileURL else { throw LocalPlaylistError.unreadableFile(title) }
        let securityScope = source.startAccessingSecurityScopedResource()
        defer { if securityScope { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw LocalPlaylistError.unreadableFile(title)
        }
        if let bytes = values.fileSize {
            if bytes > maxFileBytes { throw LocalPlaylistError.fileTooLarge(title) }
            if bytes > remainingBytes { throw LocalPlaylistError.libraryTooLarge }
        }

        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let writer = try FileHandle(forWritingTo: destination)
        defer { try? writer.close() }
        var size: Int64 = 0
        while let chunk = try reader.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            size += Int64(chunk.count)
            if size > maxFileBytes { throw LocalPlaylistError.fileTooLarge(title) }
            if size > remainingBytes { throw LocalPlaylistError.libraryTooLarge }
            try writer.write(contentsOf: chunk)
        }
        guard size > 0 else { throw LocalPlaylistError.unreadableFile(title) }
        try writer.synchronize()
        return size
    }

    nonisolated private static func metadataText(
        _ metadata: [AVMetadataItem], identifier: AVMetadataIdentifier
    ) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first else {
            return nil
        }
        return clean(try? await item.load(.stringValue))
    }

    nonisolated private static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let printable = raw.unicodeScalars.prefix(1024).map {
            CharacterSet.controlCharacters.contains($0) ? " " : String($0)
        }.joined()
        let trimmed = printable.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let limited = String(trimmed.unicodeScalars.prefix(160)).trimmingCharacters(in: .whitespaces)
        return limited.isEmpty ? nil : limited
    }
}
