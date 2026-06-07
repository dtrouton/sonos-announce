import Foundation
import AVFoundation

enum TTSGenerator {

    static func generate(text: String) async throws -> Data {
        #if os(macOS)
        return try await generateWithSay(text: text)
        #else
        return try await generateWithAVSpeech(text: text)
        #endif
    }

    // MARK: - macOS: `say` command (most reliable on Mac)

    #if os(macOS)
    private static func generateWithSay(text: String) async throws -> Data {
        let aiffPath = NSTemporaryDirectory() + "sonos_announce.aiff"
        let wavPath = NSTemporaryDirectory() + "sonos_announce.wav"

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    // Generate AIFF with say
                    let sayProcess = Process()
                    sayProcess.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                    sayProcess.arguments = ["-r", "140", "-o", aiffPath, text]
                    try sayProcess.run()
                    sayProcess.waitUntilExit()

                    guard sayProcess.terminationStatus == 0 else {
                        continuation.resume(throwing: SonosError.ttsGenerationFailed)
                        return
                    }

                    // Convert to WAV (16-bit PCM, 44100 Hz) for Sonos
                    let convertProcess = Process()
                    convertProcess.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
                    convertProcess.arguments = ["-f", "WAVE", "-d", "LEI16@44100", aiffPath, wavPath]
                    try convertProcess.run()
                    convertProcess.waitUntilExit()

                    guard convertProcess.terminationStatus == 0 else {
                        continuation.resume(throwing: SonosError.ttsGenerationFailed)
                        return
                    }

                    let data = try Data(contentsOf: URL(fileURLWithPath: wavPath))
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    #endif

    // MARK: - iOS: AVSpeechSynthesizer

    #if os(iOS)
    private static func generateWithAVSpeech(text: String) async throws -> Data {
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "sonos_announce.wav")

        return try await withCheckedThrowingContinuation { continuation in
            let synthesizer = AVSpeechSynthesizer()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

            var audioFile: AVAudioFile?
            var hasResumed = false

            synthesizer.write(utterance) { [synthesizer] buffer in
                _ = synthesizer // prevent deallocation during synthesis

                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

                // Empty buffer signals completion
                if pcmBuffer.frameLength == 0 {
                    guard !hasResumed else { return }
                    hasResumed = true
                    audioFile = nil // flush & close
                    do {
                        let data = try Data(contentsOf: outputURL)
                            continuation.resume(returning: data)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                do {
                    if audioFile == nil {
                        let settings: [String: Any] = [
                            AVFormatIDKey: Int(kAudioFormatLinearPCM),
                            AVSampleRateKey: pcmBuffer.format.sampleRate,
                            AVNumberOfChannelsKey: pcmBuffer.format.channelCount,
                            AVLinearPCMBitDepthKey: 16,
                            AVLinearPCMIsFloatKey: false,
                            AVLinearPCMIsBigEndianKey: false,
                        ]
                        audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
                    }
                    try audioFile?.write(from: pcmBuffer)
                } catch {
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    #endif
}
