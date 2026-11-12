@preconcurrency import AVFoundation
import Speech
import XCTest

/// Synthetic audio only: verifies the real on-device speech model without
/// recording ambient audio or depending on the user's private conversations.
@MainActor
final class SpeechTranscriberDeviceTests: XCTestCase {
    func testWorkoutAudioTranscribesWithLocalSpeechAssets() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MARBLE_SPEECH_ACCEPTANCE"] == "1")
        #if !targetEnvironment(simulator)
        try XCTSkipUnless(Bundle.main.object(forInfoDictionaryKey: "MarbleBundleSuffix") as? String == ".validation")
        #endif
        let supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
        #if targetEnvironment(simulator)
        try XCTSkipUnless(supported != nil, "This simulator does not provide the local English speech model; not microphone acceptance.")
        #endif
        let locale = try XCTUnwrap(supported)
        let module = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "WorkoutDictation", withExtension: "aiff"))
        let analyzer = SpeechAnalyzer(modules: [module])
        let results = Task {
            var text = ""
            for try await result in module.results {
                text += String(result.text.characters) + " "
            }
            return text
        }
        let deadline = Task {
            try? await Task.sleep(for: .seconds(90))
            if !Task.isCancelled { await analyzer.cancelAndFinishNow() }
        }
        defer { deadline.cancel() }
        do {
            try await analyzer.start(inputAudioFile: AVAudioFile(forReading: url), finishAfterFile: true)
            let text = try await results.value.lowercased()
            let attachment = XCTAttachment(string: text)
            attachment.name = "Synthetic-workout-transcript"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(text.contains("bench"), text)
            XCTAssertTrue(text.contains("press"), text)
            XCTAssertTrue(text.contains("pound"), text)
            XCTAssertTrue(text.contains("185") || text.contains("eighty"), text)
        } catch {
            await analyzer.cancelAndFinishNow()
            results.cancel()
            throw error
        }
    }
}
