import Foundation

struct DailyHighlightQuote: Equatable, Identifiable {
    let id: String
    let text: String
    let author: String
    let source: String
    let sourceURL: String
}

/// A bundled, public-domain quote schedule for Daily Highlights.
///
/// The catalog is intentionally arranged into 15 balanced cohorts. Each local
/// celebration day gets exactly one cohort, all 45 quotes appear before the
/// schedule repeats, adjacent days never share a quote, and the result is stable
/// across processes because it never relies on Swift's randomized `Hasher`.
enum DailyHighlightQuoteLibrary {
    static let quotesPerDay = 3
    static let scheduleVersion = 1

    static let all: [DailyHighlightQuote] = cohorts.flatMap { $0 }

    static func quotes(
        for day: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [DailyHighlightQuote] {
        guard !cohorts.isEmpty else { return [] }
        let dayOrdinal = calendar.ordinality(of: .day, in: .era, for: calendar.startOfDay(for: day))
            ?? fallbackDayOrdinal(for: day, calendar: calendar)

        // Seven is coprime with 15, so every cohort appears once per cycle while
        // the order feels varied instead of simply walking the source catalog.
        let index = positiveModulo(dayOrdinal * 7 + scheduleVersion * 11, cohorts.count)
        return cohorts[index]
    }

    private static func fallbackDayOrdinal(for day: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return (components.year ?? 0) * 372
            + (components.month ?? 0) * 31
            + (components.day ?? 0)
    }

    private static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }

    private static let cohorts: [[DailyHighlightQuote]] = [
        [
            quote(
                "aurelius-hold-to-action",
                "Hold to this in every action.",
                "Marcus Aurelius",
                "Meditations",
                "https://www.gutenberg.org/files/55317/55317-h/55317-h.htm"
            ),
            quote(
                "alcott-learning-to-sail",
                "I’m not afraid of storms, for I’m learning how to sail my ship.",
                "Louisa May Alcott",
                "Little Women",
                "https://www.gutenberg.org/files/514/514-h/514-h.htm"
            ),
            quote(
                "emerson-peace-yourself",
                "Nothing can bring you peace but yourself.",
                "Ralph Waldo Emerson",
                "Essays, First Series",
                "https://www.gutenberg.org/files/2944/2944-h/2944-h.htm"
            )
        ],
        [
            quote(
                "franklin-well-done",
                "Well done is better than well said.",
                "Benjamin Franklin",
                "Poor Richard’s Almanack",
                "https://founders.archives.gov/documents/Franklin/01-02-02-0028"
            ),
            quote(
                "douglass-struggle-progress",
                "If there is no struggle, there is no progress.",
                "Frederick Douglass",
                "West India Emancipation",
                "https://www.loc.gov/resource/mss11879.21039/?sp=45"
            ),
            quote(
                "thoreau-awake-alive",
                "To be awake is to be alive.",
                "Henry David Thoreau",
                "Walden",
                "https://www.gutenberg.org/cache/epub/205/pg205-images.html"
            )
        ],
        [
            quote(
                "roosevelt-nothing-without-effort",
                "In this life we get nothing save by effort.",
                "Theodore Roosevelt",
                "The Strenuous Life",
                "https://www.gutenberg.org/files/58821/58821-h/58821-h.htm"
            ),
            quote(
                "lincoln-resolution-to-succeed",
                "Always bear in mind that your own resolution to succeed, is more important than any other one thing.",
                "Abraham Lincoln",
                "Letter to Isham Reavis, 1855",
                "https://papersofabrahamlincoln.org/documents/D200867"
            ),
            quote(
                "washington-do-most-for-others",
                "Those who are happiest are those who do the most for others.",
                "Booker T. Washington",
                "Up from Slavery",
                "https://www.gutenberg.org/cache/epub/2376/pg2376-images.html"
            )
        ],
        [
            quote(
                "james-faculty-of-effort",
                "Keep the faculty of effort alive in you by a little gratuitous exercise every day.",
                "William James",
                "Talks to Teachers",
                "https://www.gutenberg.org/files/16287/16287-h/16287-h.htm"
            ),
            quote(
                "tennyson-not-to-yield",
                "To strive, to seek, to find, and not to yield.",
                "Alfred, Lord Tennyson",
                "Ulysses",
                "https://www.gutenberg.org/cache/epub/8601/pg8601.html.utf8"
            ),
            quote(
                "dickinson-hope-feathers",
                "Hope is the thing with feathers.",
                "Emily Dickinson",
                "Hope",
                "https://www.gutenberg.org/cache/epub/2679/pg2679.html"
            )
        ],
        [
            quote(
                "addams-action-expression",
                "Action indeed is the sole medium of expression for ethics.",
                "Jane Addams",
                "Democracy and Social Ethics",
                "https://www.gutenberg.org/files/15487/15487-h/15487-h.htm"
            ),
            quote(
                "bronte-independent-will",
                "I am no bird; and no net ensnares me; I am a free human being with an independent will.",
                "Charlotte Brontë",
                "Jane Eyre",
                "https://www.gutenberg.org/files/1260/1260-h/1260-h.htm"
            ),
            quote(
                "eliot-less-difficult",
                "What do we live for, if it is not to make life less difficult to each other?",
                "George Eliot",
                "Middlemarch",
                "https://www.gutenberg.org/ebooks/145"
            )
        ],
        [
            quote(
                "smiles-work-educator",
                "Work is one of the best educators of practical character.",
                "Samuel Smiles",
                "Character",
                "https://www.gutenberg.org/files/2541/2541-h/2541-h.htm"
            ),
            quote(
                "johnson-works-perseverance",
                "Great works are performed not by strength, but perseverance.",
                "Samuel Johnson",
                "Rasselas",
                "https://www.gutenberg.org/files/652/652-h/652-h.htm"
            ),
            quote(
                "whitman-i-am-enough",
                "I exist as I am, that is enough.",
                "Walt Whitman",
                "Song of Myself",
                "https://www.gutenberg.org/files/1322/old/1322-h/1322-h.htm"
            )
        ],
        [
            quote(
                "confucius-constant-perseverance",
                "Is it not pleasant to learn with a constant perseverance and application?",
                "Confucius",
                "The Analects",
                "https://www.gutenberg.org/cache/epub/3330/pg3330.html"
            ),
            quote(
                "dumas-wait-and-hope",
                "All human wisdom is summed up in these two words—wait and hope.",
                "Alexandre Dumas",
                "The Count of Monte Cristo",
                "https://www.gutenberg.org/files/1184/1184-h/1184-h"
            ),
            quote(
                "thoreau-quality-of-day",
                "To affect the quality of the day, that is the highest of arts.",
                "Henry David Thoreau",
                "Walden",
                "https://www.gutenberg.org/cache/epub/205/pg205-images.html"
            )
        ],
        [
            quote(
                "allen-dream-lofty-dreams",
                "Dream lofty dreams, and as you dream, so shall you become.",
                "James Allen",
                "As a Man Thinketh",
                "https://www.gutenberg.org/files/4507/4507-h/4507-h.htm"
            ),
            quote(
                "browning-reach-exceed-grasp",
                "A man’s reach should exceed his grasp.",
                "Robert Browning",
                "Andrea del Sarto",
                "https://www.gutenberg.org/files/12817/12817-h/12817-h.htm"
            ),
            quote(
                "seneca-foundation-of-joy",
                "The foundation of true joy is in the conscience.",
                "Seneca",
                "Seneca’s Morals",
                "https://www.gutenberg.org/cache/epub/56075/pg56075-images.html"
            )
        ],
        [
            quote(
                "washington-idea-could-succeed",
                "I have begun everything with the idea that I could succeed.",
                "Booker T. Washington",
                "Up from Slavery",
                "https://www.gutenberg.org/cache/epub/2376/pg2376-images.html"
            ),
            quote(
                "montgomery-tomorrow-new-day",
                "Isn’t it nice to think that tomorrow is a new day with no mistakes in it yet?",
                "L. M. Montgomery",
                "Anne of Green Gables",
                "https://www.gutenberg.org/files/45/45-h/45-h.htm"
            ),
            quote(
                "aurelius-while-you-live",
                "While you live, while yet you may, be good.",
                "Marcus Aurelius",
                "Meditations",
                "https://www.gutenberg.org/files/55317/55317-h/55317-h.htm"
            )
        ],
        [
            quote(
                "franklin-lost-time",
                "Lost Time is never found again.",
                "Benjamin Franklin",
                "Poor Richard’s Almanack",
                "https://founders.archives.gov/documents/Franklin/01-03-02-0103"
            ),
            quote(
                "epictetus-be-invincible",
                "You can be invincible, if you enter into no contest in which it is not in your power to conquer.",
                "Epictetus",
                "Discourses and Encheiridion",
                "https://www.gutenberg.org/cache/epub/10661/pg10661-images.html"
            ),
            quote(
                "emerson-self-trust-heroism",
                "Self-trust is the essence of heroism.",
                "Ralph Waldo Emerson",
                "Essays, First Series",
                "https://www.gutenberg.org/files/2944/2944-h/2944-h.htm"
            )
        ],
        [
            quote(
                "wollstonecraft-rational-free",
                "Make women rational creatures and free citizens.",
                "Mary Wollstonecraft",
                "A Vindication of the Rights of Woman",
                "https://www.gutenberg.org/cache/epub/3420/pg3420.html"
            ),
            quote(
                "douglass-power-demand",
                "Power concedes nothing without a demand.",
                "Frederick Douglass",
                "West India Emancipation",
                "https://www.loc.gov/resource/mss11879.21039/?sp=45"
            ),
            quote(
                "burnett-beautiful-thoughts",
                "When new beautiful thoughts began to push out the old hideous ones, life began to come back to him.",
                "Frances Hodgson Burnett",
                "The Secret Garden",
                "https://www.gutenberg.org/files/17396/17396-h/17396-h.htm"
            )
        ],
        [
            quote(
                "cervantes-diligence-fortune",
                "Diligence is the mother of good fortune.",
                "Miguel de Cervantes",
                "Don Quixote",
                "https://www.gutenberg.org/cache/epub/996/pg996-images.html"
            ),
            quote(
                "stevenson-capable-of-becoming",
                "To be what we are, and to become what we are capable of becoming, is the only end of life.",
                "Robert Louis Stevenson",
                "Lay Morals",
                "https://www.gutenberg.org/cache/epub/2537/pg2537-images.html"
            ),
            quote(
                "wilde-experience-mistakes",
                "Experience is the name every one gives to their mistakes.",
                "Oscar Wilde",
                "Lady Windermere’s Fan",
                "https://www.gutenberg.org/files/790/790-h/790-h"
            )
        ],
        [
            quote(
                "confucius-small-matters",
                "Want of forbearance in small matters confounds great plans.",
                "Confucius",
                "The Analects",
                "https://www.gutenberg.org/cache/epub/3330/pg3330.html"
            ),
            quote(
                "roosevelt-tried-to-succeed",
                "It is hard to fail, but it is worse never to have tried to succeed.",
                "Theodore Roosevelt",
                "The Strenuous Life",
                "https://www.gutenberg.org/files/58821/58821-h/58821-h.htm"
            ),
            quote(
                "dickens-lightens-burden",
                "No one is useless in this world who lightens the burden of it for any one else.",
                "Charles Dickens",
                "Our Mutual Friend",
                "https://www.gutenberg.org/cache/epub/883/pg883-images.html"
            )
        ],
        [
            quote(
                "allen-dreams-seedlings",
                "Dreams are the seedlings of realities.",
                "James Allen",
                "As a Man Thinketh",
                "https://www.gutenberg.org/files/4507/4507-h/4507-h.htm"
            ),
            quote(
                "vivekananda-awake-arise",
                "Awake, arise, and stop not until the goal is reached.",
                "Swami Vivekananda",
                "Jnâna Yoga, Part II",
                "https://www.gutenberg.org/cache/epub/72368/pg72368-images.html"
            ),
            quote(
                "thoreau-simplify",
                "Simplify, simplify.",
                "Henry David Thoreau",
                "Walden",
                "https://www.gutenberg.org/cache/epub/205/pg205-images.html"
            )
        ],
        [
            quote(
                "james-spectacle-of-effort",
                "The spectacle of effort is what awakens and sustains our own effort.",
                "William James",
                "Talks to Teachers",
                "https://www.gutenberg.org/files/16287/16287-h/16287-h.htm"
            ),
            quote(
                "montgomery-mistake-twice",
                "I never make the same mistake twice.",
                "L. M. Montgomery",
                "Anne of Green Gables",
                "https://www.gutenberg.org/files/45/45-h/45-h.htm"
            ),
            quote(
                "emerson-trust-thyself",
                "Trust thyself: every heart vibrates to that iron string.",
                "Ralph Waldo Emerson",
                "Essays, First Series",
                "https://www.gutenberg.org/files/2944/2944-h/2944-h.htm"
            )
        ]
    ]

    private static func quote(
        _ id: String,
        _ text: String,
        _ author: String,
        _ source: String,
        _ sourceURL: String
    ) -> DailyHighlightQuote {
        DailyHighlightQuote(
            id: id,
            text: text,
            author: author,
            source: source,
            sourceURL: sourceURL
        )
    }
}
