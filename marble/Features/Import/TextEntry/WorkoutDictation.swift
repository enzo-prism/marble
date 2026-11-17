@preconcurrency import AVFoundation
import Foundation
import Observation
import Speech
import SwiftData
import SwiftUI
import UIKit

/// Push-to-talk capture only. Final text enters the existing editable review pipeline.
///
/// Uses the progressive preset: in-progress ("volatile") words appear live and are
/// replaced as the analyzer finalizes them. Only `transcript` — finalized text plus
/// whatever is still volatile — leaves this type; Stop finalizes through the end of
/// input first, so Use Text receives settled words.
@MainActor
@Observable
final class WorkoutDictation {
    private var text = WorkoutDictationTranscript()
    /// Words the analyzer has committed to.
    var finalizedTranscript: String { text.finalized }
    /// The current best guess for words still being spoken; replaced on every update.
    var volatileTranscript: String { text.volatile }
    /// Finalized text followed by any volatile tail.
    var transcript: String { text.combined }
    /// Exercise names and gym jargon biasing recognition. Set before `start()`.
    @ObservationIgnored var contextualStrings: [String] = []
    private(set) var isPreparing = false
    private(set) var isRecording = false
    private(set) var errorMessage: String?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var resultTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    private let requestRecordPermission: @MainActor () async -> Bool
    private let audioSession = WorkoutDictationAudioSession()

    init(requestRecordPermission: @escaping @MainActor () async -> Bool = {
        await AVAudioApplication.requestRecordPermission()
    }) {
        self.requestRecordPermission = requestRecordPermission
    }

    func start() async {
        guard !isPreparing, !isRecording, !Task.isCancelled else { return }
        generation += 1
        let expected = generation
        isPreparing = true
        errorMessage = nil
        defer { if generation == expected { isPreparing = false } }
        let permissionGranted = await requestRecordPermission()
        guard expected == generation, !Task.isCancelled else { return }
        guard permissionGranted else {
            errorMessage = "Microphone access is off. Enable it for Marble in Settings, or type your workout."
            return
        }
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
        guard expected == generation, !Task.isCancelled else { return }
        guard let locale else {
            errorMessage = "Dictation is unavailable for this language. You can still type or paste your workout."
            return
        }
        do {
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                guard expected == generation, !Task.isCancelled else { return }
                try await installation.downloadAndInstall()
            }
            guard expected == generation, !Task.isCancelled,
                  UIApplication.shared.applicationState == .active else { return }
            try await audioSession.activate(generation: expected)
            guard expected == generation, !Task.isCancelled,
                  UIApplication.shared.applicationState == .active else {
                await audioSession.deactivate(generation: expected)
                return
            }
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let nativeFormat = input.outputFormat(forBus: 0)
            guard nativeFormat.sampleRate > 0,
                  let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: nativeFormat),
                  let converter = AVAudioConverter(from: nativeFormat, to: format) else {
                throw CaptureError.unavailable
            }
            guard expected == generation, !Task.isCancelled,
                  UIApplication.shared.applicationState == .active else {
                await audioSession.deactivate(generation: expected)
                return
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            // Vocabulary is a hint: the context must be in place before analysis
            // starts, and a module that rejects it still transcribes normally.
            if !contextualStrings.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = contextualStrings
                try? await analyzer.setContext(context)
                guard expected == generation, !Task.isCancelled,
                      UIApplication.shared.applicationState == .active else {
                    await analyzer.cancelAndFinishNow()
                    await audioSession.deactivate(generation: expected)
                    return
                }
            }
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            let bridge = SpeechAudioBridge(converter: converter, format: format, continuation: continuation)
            input.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { @Sendable buffer, _ in bridge.accept(buffer) }
            self.engine = engine
            self.analyzer = analyzer
            self.continuation = continuation
            resultTask = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        guard let self, self.generation == expected else { return }
                        self.text.apply(String(result.text.characters), isFinal: result.isFinal)
                    }
                } catch {
                    guard let self, self.generation == expected else { return }
                    self.errorMessage = "Dictation stopped. Your captured text is still available."
                }
            }
            analysisTask = Task { [weak self] in
                do { try await analyzer.start(inputSequence: stream) }
                catch {
                    guard let self, self.generation == expected, self.analyzer != nil else { return }
                    self.errorMessage = "Couldn't read the microphone. Try again or type your workout."
                    await self.stop()
                }
            }
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            guard expected == generation, !Task.isCancelled else { return }
            errorMessage = "Couldn't start dictation. Check your microphone and try again."
            await stop()
        }
    }

    func stop() async {
        let stoppingGeneration = generation
        // Invalidate an outstanding permission/asset request, while letting a
        // running analyzer deliver its final words during normal Stop.
        if isPreparing {
            generation += 1
            isPreparing = false
        }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        continuation?.finish()
        continuation = nil
        let activeAnalyzer = analyzer
        self.analyzer = nil
        let finalResults = resultTask
        resultTask = nil
        analysisTask = nil
        if let activeAnalyzer {
            do { try await activeAnalyzer.finalizeAndFinishThroughEndOfInput() }
            catch { await activeAnalyzer.cancelAndFinishNow() }
        }
        await finalResults?.value
        if generation == stoppingGeneration {
            // Anything the analyzer could not finalize (for example after a failed
            // finalize) is still what the person said; keep it as settled text.
            text.commitVolatile()
            isRecording = false
        }
        await audioSession.deactivate(generation: stoppingGeneration)
    }

    func cancel() {
        let cancelledGeneration = generation
        generation += 1
        isPreparing = false
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        continuation?.finish()
        continuation = nil
        analysisTask?.cancel()
        resultTask?.cancel()
        analysisTask = nil
        resultTask = nil
        if let analyzer { Task { await analyzer.cancelAndFinishNow() } }
        analyzer = nil
        isRecording = false
        let audioSession = audioSession
        Task { await audioSession.deactivate(generation: cancelledGeneration) }
    }

    private enum CaptureError: Error { case unavailable }
}

/// Finalized text plus the volatile tail a progressive transcriber keeps revising.
nonisolated struct WorkoutDictationTranscript: Equatable, Sendable {
    private(set) var finalized = ""
    private(set) var volatile = ""

    var combined: String { Self.join(finalized, volatile) }

    /// A volatile result replaces the previous volatile text; a final result is
    /// appended to the finalized text and clears the volatile tail it settles.
    mutating func apply(_ text: String, isFinal: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            finalized = Self.join(finalized, trimmed)
            volatile = ""
        } else {
            volatile = trimmed
        }
    }

    mutating func commitVolatile() {
        guard !volatile.isEmpty else { return }
        finalized = Self.join(finalized, volatile)
        volatile = ""
    }

    private static func join(_ head: String, _ tail: String) -> String {
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        return head + " " + tail
    }
}

/// Words the speech model should expect: the lifter's own exercise names, most
/// recently used first, then gym shorthand that general dictation mangles.
nonisolated enum WorkoutDictationVocabulary {
    /// Contextual strings are a bias, not a grammar; a bounded list keeps the
    /// hint focused on what this lifter actually trains.
    static let maximumExerciseNames = 100

    static let gymJargon = [
        "RDL", "Romanian deadlift", "DB", "dumbbell", "BB", "barbell", "KB", "kettlebell",
        "AMRAP", "EMOM", "RPE", "PR", "superset", "drop set", "Bulgarian split squat",
        "OHP", "overhead press", "pull-up", "chin-up", "push-up", "hip thrust",
        "lat pulldown", "face pull", "skull crusher", "Tabata", "WOD"
    ]

    /// Recent names first, then the rest of the library, capped at `limit`
    /// distinct names (case-insensitive); jargon is appended when not already named.
    static func strings(recentExerciseNames: [String], libraryExerciseNames: [String],
                        limit: Int = maximumExerciseNames) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for raw in recentExerciseNames + libraryExerciseNames where names.count < limit {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            names.append(name)
        }
        let jargon = gymJargon.filter { seen.insert($0.lowercased()).inserted }
        return names + jargon
    }

    /// Reads the library from SwiftData: exercise names in order of the newest
    /// logged sets (a bounded window), then favorites, then the rest by name.
    @MainActor
    static func strings(in context: ModelContext, recentSetWindow: Int = 500) -> [String] {
        var recent = FetchDescriptor<SetEntry>(sortBy: [SortDescriptor(\.performedAt, order: .reverse)])
        recent.fetchLimit = recentSetWindow
        let recentNames = ((try? context.fetch(recent)) ?? []).map { $0.exercise.name }
        let library = (try? context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)]))) ?? []
        let libraryNames = library.filter(\.isFavorite).map(\.name) + library.filter { !$0.isFavorite }.map(\.name)
        return strings(recentExerciseNames: recentNames, libraryExerciseNames: libraryNames)
    }
}

/// AVAudioSession activation can block. Keep it off the UI actor and serialize
/// ownership so an old Stop/Cancel cannot deactivate a newer recording.
actor WorkoutDictationAudioSession {
    private var highestGeneration = 0
    private var invalidatedThrough = 0
    private var activeGeneration: Int?
    private let performActivation: @Sendable () throws -> Void
    private let performDeactivation: @Sendable () -> Void

    init(activate: @escaping @Sendable () throws -> Void = {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)
    }, deactivate: @escaping @Sendable () -> Void = {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }) {
        performActivation = activate
        performDeactivation = deactivate
    }

    func activate(generation: Int) throws {
        guard generation > invalidatedThrough, generation >= highestGeneration else { throw CancellationError() }
        highestGeneration = generation
        try performActivation()
        activeGeneration = generation
    }

    func deactivate(generation: Int) {
        invalidatedThrough = max(invalidatedThrough, generation)
        guard activeGeneration == generation else { return }
        performDeactivation()
        activeGeneration = nil
    }
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
    @Environment(\.modelContext) private var modelContext
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
                    transcriptText
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
        .task {
            capture.contextualStrings = WorkoutDictationVocabulary.strings(in: modelContext)
            await capture.start()
        }
        .onChange(of: scenePhase) { _, phase in
            // The permission sheet itself makes the scene inactive. Background
            // always cancels setup; inactive stops only an existing recording.
            if phase == .background || (phase == .inactive && capture.isRecording) {
                Task { await capture.stop() }
            }
        }
        .onDisappear { capture.cancel() }
    }

    /// Settled words in the primary style; words still being recognized follow in
    /// the secondary style and are replaced as the analyzer finalizes them.
    private var transcriptText: Text {
        if capture.transcript.isEmpty { return Text("Your words will appear here.") }
        if capture.volatileTranscript.isEmpty { return Text(capture.finalizedTranscript) }
        let separator = capture.finalizedTranscript.isEmpty ? "" : " "
        return Text("\(Text(capture.finalizedTranscript + separator))\(Text(capture.volatileTranscript).foregroundStyle(.secondary))")
    }
}
