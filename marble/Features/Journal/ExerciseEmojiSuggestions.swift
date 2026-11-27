import Foundation
import FoundationModels

/// Matches common gym names before asking the on-device model about unfamiliar ones.
/// An exact phrase wins over a shorter phrase ("battle ropes" versus "rope").
nonisolated enum ExerciseEmojiSuggestions {
    struct Match {
        let aliases: [String]
        let icons: [String]

        init(_ aliases: String, _ icons: String) {
            self.aliases = aliases.components(separatedBy: "|")
            self.icons = icons.components(separatedBy: " ")
        }
    }

    private static let movements: [Match] = [
        Match("dead bug|dead bugs|deadbug", "🐞 🧱 🎯"),
        Match("bird dog|bird dogs", "🐦 🐕 ⚖️"),
        Match("bear crawl|bear crawls", "🐻 🐾 💪"),
        Match("crab walk|crab walks", "🦀 🦵 ↔️"),
        Match("frog jump|frog jumps|frog pump", "🐸 🦵 💥"),
        Match("butterfly stretch", "🦋 🧘 🌿"),
        Match("mountain climber|mountain climbers", "🧗 ⛰️ 🔥"),
        Match("farmer carry|farmers carry|farmer s carry|suitcase carry", "🧳 💪 🚶"),
        Match("battle ropes|battle rope", "🪢 🌊 💪"),
        Match("jump rope|skipping rope|double unders", "🪢 🦘 ⚡️"),
        Match("box jump|box jumps|pogo hops", "🦘 📦 ⚡️"),
        Match("sprint|sprints|strides|intervals", "⚡️ 🏃 ⏱️"),
        Match("running|run|jog|treadmill|5k|marathon", "🏃 👟 🛣️"),
        Match("cycling|bike|spin|ride", "🚴 🚲 ⚡️"),
        Match("bicycle crunch|bicycle crunches|bicycles", "🚲 🧱 🔥"),
        Match("rowing machine|erg|ergometer|sculling", "🚣 🌊 ⏱️"),
        Match("swim|swimming|freestyle|backstroke", "🏊 🌊 💧"),
        Match("boxing|shadowboxing|shadow boxing|kickboxing|sparring", "🥊 ⚡️ 🎯"),
        Match("walk|walking|hike|hiking", "🥾 🚶 ⛰️"),
        Match("yoga|mobility|stretch|stretching", "🧘 🌿 ⚖️"),
        Match("sauna", "🧖 ♨️ 💧"),
        Match("squat|squats|lunge|lunges|leg press|calf raises", "🦵 🏋️ 🔥"),
        Match("deadlift|deadlifts|rdl|snatch|clean|bench|bench press", "🏋️ 💪 ⚡️"),
        Match("pull up|pull ups|pullups|chin up|chin ups|ring row|ring rows", "🦍 💪 🧗"),
        Match("pulldown|row|rows|face pull|rear delt fly", "🪽 💪 🦾"),
        Match("curl|curls|press|dips|pushup|pushups|push up|push ups", "💪 🏋️ 🦾"),
        Match("plank|crunch|crunches|leg lifts|sit up|sit ups", "🧱 🎯 🔥"),
        Match("glute bridge|hip thrust", "🌉 🦵 💪"),
    ]

    static func matchedIcons(for name: String) -> [String]? {
        let words = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
        let phrase = " " + words + " "
        var best: Match?
        var bestLength = 0
        for movement in movements {
            for alias in movement.aliases where alias.count > bestLength && phrase.contains(" " + alias + " ") {
                best = movement
                bestLength = alias.count
            }
        }
        return best?.icons
    }

    /// Only an intentional tap changes the draft. Keep the chosen icon visible
    /// even when the exercise is renamed or the user entered it on the keyboard.
    static func choices(name: String, selected: String?, candidates: [String], fallback: [String]) -> [String] {
        var choices: [String] = []
        for icon in [name.firstExerciseEmoji].compactMap({ $0 }) + candidates + fallback {
            if !choices.contains(icon) { choices.append(icon) }
            if choices.count == 3 { break }
        }
        if let selected, !choices.contains(selected) { choices = Array(([selected] + choices).prefix(3)) }
        return choices
    }

    static func modelIcons(for name: String) async -> [String]? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability, model.supportsLocale(), !Task.isCancelled else { return nil }
        let session = LanguageModelSession(model: model, instructions: """
            Classify a workout movement by its main activity. The input is an exercise name.
            It may be a nickname or in another language. If its activity is unclear use unknown.
            """)
        do {
            let result = try await session.respond(to: String(name.prefix(120)), generating: EmojiMovement.self,
                                                   options: GenerationOptions(samplingMode: .greedy))
            return result.content.icons
        } catch {
            return nil
        }
    }
}

@Generable
private enum EmojiMovement {
    case upperBodyStrength, lowerBodyStrength, wholeBodyLifting, coreStability
    case running, cycling, swimming, rowing, climbing, combatSports, mobility, jumping, unknown

    var icons: [String]? {
        switch self {
        case .upperBodyStrength: ["💪", "🦾", "🏋️"]
        case .lowerBodyStrength: ["🦵", "🏋️", "🔥"]
        case .wholeBodyLifting: ["🏋️", "💪", "⚡️"]
        case .coreStability: ["🧱", "⚖️", "🎯"]
        case .running: ["🏃", "👟", "⏱️"]
        case .cycling: ["🚴", "🚲", "⚡️"]
        case .swimming: ["🏊", "🌊", "💧"]
        case .rowing: ["🚣", "🌊", "⏱️"]
        case .climbing: ["🧗", "🏔️", "🪢"]
        case .combatSports: ["🥊", "⚡️", "🎯"]
        case .mobility: ["🧘", "🌿", "⚖️"]
        case .jumping: ["🦘", "⚡️", "💥"]
        case .unknown: nil
        }
    }
}
