import Foundation

struct TestAudioFixture {
    let directory: URL

    var playlistDirectory: URL {
        directory.appendingPathComponent("Playlist", isDirectory: true)
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "personal-radio-test-" + UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    func makeFile(_ filename: String, contents: Data) throws -> URL {
        let url = directory.appendingPathComponent(filename)
        try contents.write(to: url)
        return url
    }

    func makeWAV(_ filename: String, frames: Int = 800, sampleRate: Int = 8_000) throws -> URL {
        // Mono 16-bit PCM silence. The duration is controlled by the frame count.
        let frameBytes = MemoryLayout<Int16>.size
        let payloadBytes = UInt32(frames * frameBytes)
        var wave = Data("RIFF".utf8)
        Self.append(36 + payloadBytes, to: &wave)
        wave.append(contentsOf: "WAVEfmt ".utf8)
        Self.append(UInt32(16), to: &wave)
        Self.append(UInt16(1), to: &wave)
        Self.append(UInt16(1), to: &wave)
        Self.append(UInt32(sampleRate), to: &wave)
        Self.append(UInt32(sampleRate * frameBytes), to: &wave)
        Self.append(UInt16(frameBytes), to: &wave)
        Self.append(UInt16(frameBytes * 8), to: &wave)
        wave.append(contentsOf: "data".utf8)
        Self.append(payloadBytes, to: &wave)
        wave.append(Data(count: Int(payloadBytes)))
        return try makeFile(filename, contents: wave)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func append<T: FixedWidthInteger>(_ number: T, to data: inout Data) {
        var littleEndian = number.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
