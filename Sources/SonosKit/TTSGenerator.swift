import Foundation
import AVFoundation

/// Parse a canonical PCM WAV header and compute playback duration in seconds.
/// Reads sample rate, channel count, and bit depth from the header rather than
/// assuming 44.1kHz mono. Returns 0 for data too short to contain a header.
public func wavDuration(data: Data) -> TimeInterval {
    guard data.count >= 44 else { return 0 }
    func u16(_ off: Int) -> UInt16 {
        UInt16(data[data.startIndex + off]) | (UInt16(data[data.startIndex + off + 1]) << 8)
    }
    func u32(_ off: Int) -> UInt32 {
        UInt32(data[data.startIndex + off]) | (UInt32(data[data.startIndex + off + 1]) << 8)
            | (UInt32(data[data.startIndex + off + 2]) << 16) | (UInt32(data[data.startIndex + off + 3]) << 24)
    }
    let channels = max(1, Int(u16(22)))
    let sampleRate = max(1, Int(u32(24)))
    let bits = max(1, Int(u16(34)))
    let dataBytes = Int(u32(40))
    let bytesPerFrame = channels * (bits / 8)
    guard bytesPerFrame > 0 else { return 0 }
    return Double(dataBytes) / Double(sampleRate * bytesPerFrame)
}

public enum TTSGenerator {

    /// Generate 16-bit PCM WAV audio for `text` using AVSpeechSynthesizer on all
    /// platforms. Returns the WAV bytes.
    public static func generate(text: String) async throws -> Data {
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sonos_announce_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        return try await withCheckedThrowingContinuation { continuation in
            let synthesizer = AVSpeechSynthesizer()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate

            var audioFile: AVAudioFile?
            var hasResumed = false

            synthesizer.write(utterance) { [synthesizer] buffer in
                _ = synthesizer // retain during synthesis
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }

                if pcm.frameLength == 0 {
                    guard !hasResumed else { return }
                    hasResumed = true
                    audioFile = nil // flush & close
                    do {
                        continuation.resume(returning: try Data(contentsOf: outputURL))
                    } catch {
                        continuation.resume(throwing: SonosError.ttsGenerationFailed)
                    }
                    return
                }

                do {
                    if audioFile == nil {
                        let settings: [String: Any] = [
                            AVFormatIDKey: Int(kAudioFormatLinearPCM),
                            AVSampleRateKey: pcm.format.sampleRate,
                            AVNumberOfChannelsKey: pcm.format.channelCount,
                            AVLinearPCMBitDepthKey: 16,
                            AVLinearPCMIsFloatKey: false,
                            AVLinearPCMIsBigEndianKey: false,
                        ]
                        audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
                    }
                    try audioFile?.write(from: pcm)
                } catch {
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(throwing: SonosError.ttsGenerationFailed)
                }
            }
        }
    }
}
