import XCTest
@testable import SonosKit

final class WavDurationTests: XCTestCase {
    /// Build a canonical 44-byte PCM WAV header for the given params plus
    /// `dataBytes` of silence, then assert the parsed duration.
    private func makeWAV(sampleRate: UInt32, channels: UInt16, bits: UInt16, dataBytes: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(Data("RIFF".utf8)); u32(UInt32(36 + dataBytes)); d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); u32(16); u16(1); u16(channels); u32(sampleRate)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bits / 8)
        u32(byteRate); u16(channels * bits / 8); u16(bits)
        d.append(Data("data".utf8)); u32(UInt32(dataBytes))
        d.append(Data(repeating: 0, count: dataBytes))
        return d
    }

    func testMono44100() {
        let wav = makeWAV(sampleRate: 44100, channels: 1, bits: 16, dataBytes: 44100)
        XCTAssertEqual(wavDuration(data: wav), 0.5, accuracy: 0.001)
    }

    func testStereo22050() {
        let wav = makeWAV(sampleRate: 22050, channels: 2, bits: 16, dataBytes: 88200)
        XCTAssertEqual(wavDuration(data: wav), 1.0, accuracy: 0.001)
    }

    func testTooShortReturnsZero() {
        XCTAssertEqual(wavDuration(data: Data([0x52, 0x49])), 0, accuracy: 0.0001)
    }
}
