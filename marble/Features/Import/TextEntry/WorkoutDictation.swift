@preconcurrency import AVFoundation
import Foundation
import Observation
import Speech
import SwiftUI

/// Push-to-talk capture only. Final text enters the existing editable review pipeline.
@MainActor
@Observable
final class WorkoutDictation {
    private(set) var transcript = ""
    private(set) var isPreparing = false
    private(set) var isRecording = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var resultTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    func start() async {
        guard !isPreparing, !isRecording else { return }
        generation += 1
        let expected = generation
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Microphone access is off. Enable it for Marble in Settings, or type your workout."
            return
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            errorMessage = "Dictation is unavailable for this language. You can still type or paste your workout."
            return
        }
        do {
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installation.downloadAndInstall()
            }
            guard expected == generation, !Task.isCancelled else { return }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let nativeFormat = input.outputFormat(forBus: 0)
            guard nativeFormat.sampleRate > 0,
                  let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: nativeFormat),
                  let converter = AVAudioConverter(from: nativeFormat, to: format) else {
                throw CaptureError.unavailable
            }
            guard expected == generation, !Task.isCancelled else {
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            let bridge = SpeechAudioBridge(converter: converter, format: format, continuation: continuation)
            input.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { @Sendable buffer, _ in bridge.accept(buffer) }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.engine = engine
            self.analyzer = analyzer
            self.continuation = continuation
            resultTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self, self.generation == expected else { return }
                        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty { self.transcript += (self.transcript.isEmpty ? "" : " ") + text }
                    }
                } catch {
                    guard let self, self.generation == expected else { return }
                    self.errorMessage = "Dictation stopped. Your captured text is still available."
                }
            }
            analysisTask = Task { [weak self] in
                do { try await analyzer.start(inputSequence: stream) }
                catch {
                    guard let self, self.generation == expected else { return }
                    self.errorMessage = "Couldn't read the microphone. Try again or type your workout."
                    await self.stop()
                }
            }
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            errorMessage = "Couldn't start dictation. Check your microphone and try again."
            await stop()
        }
    }

    func stop() async {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        continuation?.finish()
        continuation = nil
        let activeAnalyzer = analyzer
        self.analyzer = nil
        if let activeAnalyzer {
            do { try await activeAnalyzer.finalizeAndFinishThroughEndOfInput() }
            catch { await activeAnalyzer.cancelAndFinishNow() }
        }
        await resultTask?.value
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        generation += 1
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        continuation?.finish()
        continuation = nil
        analysisTask?.cancel()
        resultTask?.cancel()
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private enum CaptureError: Error { case unavailable }
}

/// AVAudioEngine delivers tap buffers serially. Conversion stays on that callback;
/// the only value crossing to SpeechAnalyzer is its Sendable AnalyzerInput.
private nonisolated final class SpeechAudioBridge: @unchecked Sendable {
    let converter: AVAudioConverter
    let format: AVAudioFormat
    let continuation: AsyncStream<AnalyzerInput>.Continuation
    init(converter: AVAudioConverter, format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        self.converter = converter; self.format = format; self.continuation = continuation
    }
    func accept(_ input: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate))
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        if error == nil, output.frameLength > 0 { continuation.yield(AnalyzerInput(buffer: output)) }
    }
}

struct WorkoutDictationSheet: View {
    let onUseText: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var capture = WorkoutDictation()
    @State private var isFinishing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Say your workout").font(.title2.bold())
                    Text("Include the exercise, sets, reps, weight and units. You can edit everything before saving.")
                        .foregroundStyle(.secondary)
                    if capture.isPreparing { ProgressView("Preparing dictation…") }
                    Text(capture.transcript.isEmpty ? "Your words will appear here." : capture.transcript)
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("Dictation.Transcript")
                    if let message = capture.errorMessage { Text(message).foregroundStyle(.secondary) }
                    Button(capture.isRecording ? "Stop Recording" : "Record", systemImage: capture.isRecording ? "stop.circle" : "mic") {
                        Task { if capture.isRecording { await capture.stop() } else { await capture.start() } }
                    }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                    .disabled(capture.isPreparing || isFinishing)
                    .accessibilityIdentifier("Dictation.Record")
                    Button("Use Text", systemImage: "checkmark") {
                        isFinishing = true
                        Task {
                            await capture.stop()
                            onUseText(capture.transcript)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(.primary).frame(minHeight: 44)
                    .disabled(capture.transcript.isEmpty || isFinishing)
                    .accessibilityIdentifier("Dictation.UseText")
                }.padding()
            }
            .navigationTitle("Dictate Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { capture.cancel(); dismiss() }.accessibilityIdentifier("Dictation.Cancel")
                }
            }
        }
        .task { await capture.start() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await capture.stop() } } }
        .onDisappear { capture.cancel() }
    }
}
