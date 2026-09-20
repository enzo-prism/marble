import Foundation

/// Short, attributed athlete quotations verified against the linked interviews,
/// athlete-authored articles, or official publications. These contemporary
/// quotations are separate from the historical public-domain catalogs.
/// Both quote surfaces apply the rendered-width filter before rotation;
/// a character limit alone cannot guarantee a single line with Dynamic Type.
enum AthleteQuotes {
    static let quotes: [DailyHighlightQuote] = [
        DailyHighlightQuote(
            id: "athlete-king-pressure",
            text: "Pressure is a privilege.",
            author: "Billie Jean King",
            source: "Billie Jean King Enterprises — Marketing",
            sourceURL: "https://www.billiejeanking.com/bjk-enterprises/marketing/"
        ),
        DailyHighlightQuote(
            id: "athlete-king-adjust",
            text: "Champions adjust.",
            author: "Billie Jean King",
            source: "Billie Jean King Leadership Initiative — 2022 Impact Report",
            sourceURL: "https://billiejeankingfoundation.org/wp-content/uploads/2022/12/ImpactReport22_1.HighRez.pdf"
        ),
        DailyHighlightQuote(
            id: "athlete-bryant-job",
            text: "Job’s not finished.",
            author: "Kobe Bryant",
            source: "NBA — 2009 Finals Game 2 post-game interview",
            sourceURL: "https://www.nba.com/watch/video/kobe-bryant-exclaims-the-jobs-not-finished-post-game-sound-from-game-2-of-the-2009-nba-finals"
        ),
        DailyHighlightQuote(
            id: "athlete-federer-trust",
            text: "Trusting yourself is a talent.",
            author: "Roger Federer",
            source: "Dartmouth — 2024 Commencement Address",
            sourceURL: "https://home.dartmouth.edu/news/2024/06/2024-commencement-address-roger-federer"
        ),
        DailyHighlightQuote(
            id: "athlete-kipchoge-limits",
            text: "No human is limited.",
            author: "Eliud Kipchoge",
            source: "INEOS 1:59 Challenge — No Human is Limited",
            sourceURL: "https://www.ineos159challenge.com/news/chris-froome-supports-eliud-kipchoge-in-his-bid-to-inspire-the-world-that-no-human-is-limited"
        ),
        DailyHighlightQuote(
            id: "athlete-felix-belief",
            text: "I always believe in myself.",
            author: "Allyson Felix",
            source: "Team USA — Allyson Felix Wins Bronze in 400 at Age 35",
            sourceURL: "https://www.teamusa.com/news/2021/august/06/number-10-five-time-olympian-allyson-felix-wins-bronze-in-400-at-age-35"
        ),
        DailyHighlightQuote(
            id: "athlete-biles-confidence",
            text: "I can do this. I know it.",
            author: "Simone Biles",
            source: "USA Gymnastics — Simone Biles Stands Tall",
            sourceURL: "https://usagym.org/simone-biles-stands-tall/"
        ),
        DailyHighlightQuote(
            id: "athlete-zmeskal-focus",
            text: "One thing at a time.",
            author: "Kim Zmeskal",
            source: "USA Gymnastics — Simone Biles Stands Tall (Zmeskal interview)",
            sourceURL: "https://usagym.org/simone-biles-stands-tall/"
        ),
        DailyHighlightQuote(
            id: "athlete-kipyegon-confidence",
            text: "I am always confident I can win.",
            author: "Faith Kipyegon",
            source: "World Athletics — Kipyegon prepares to defend world 1500m title",
            sourceURL: "https://worldathletics.org/competitions/world-athletics-championships/iaaf-world-athletics-championships-doha-2019-7125365/news/feature/faith-kipyegon-2019-kenya-1500m-child"
        ),
        DailyHighlightQuote(
            id: "athlete-williams-mills-patience",
            text: "Sometimes things take time.",
            author: "Novlene Williams-Mills",
            source: "World Athletics — Words of Wisdom: Novlene Williams-Mills",
            sourceURL: "https://worldathletics.org/spikes/news/novlene-williams-mills-words-of-wisdom"
        ),
        DailyHighlightQuote(
            id: "athlete-aman-persistence",
            text: "I never give up in training.",
            author: "Mohammed Aman",
            source: "World Athletics — Best of Words of Wisdom",
            sourceURL: "https://worldathletics.org/spikes/news/the-best-of-spikes-words-of-wisdom"
        ),
        DailyHighlightQuote(
            id: "athlete-barshim-smart",
            text: "You need to train smart.",
            author: "Mutaz Essa Barshim",
            source: "World Athletics — Words of Wisdom: Mutaz Barshim",
            sourceURL: "https://worldathletics.org/spikes/news/mutaz-barshims-words-of-wisdom"
        ),
        DailyHighlightQuote(
            id: "athlete-morris-perspective",
            text: "Sometimes you lose, sometimes you win.",
            author: "Sandi Morris",
            source: "World Athletics — I can do this",
            sourceURL: "https://worldathletics.org/spikes/news/sandi-morris-pole-vault-dream-spikes"
        ),
        DailyHighlightQuote(
            id: "athlete-ibarguen-learning",
            text: "It’s all about learning in athletics.",
            author: "Caterine Ibargüen",
            source: "World Athletics — Personal bests: Caterine Ibarguen",
            sourceURL: "https://worldathletics.org/news/series/caterine-ibarguen-colombia-triple-jump"
        ),
        DailyHighlightQuote(
            id: "athlete-ledecky-focus",
            text: "I just stay focused on my own goals.",
            author: "Katie Ledecky",
            source: "Team USA — Katie Ledecky Remains Focused on Her Goals",
            sourceURL: "https://www.teamusa.com/news/2024/july/28/katie-ledecky-kicks-off-swimming-in-paris-remains-focused-on-her-goals"
        ),
        DailyHighlightQuote(
            id: "athlete-sjostrom-courage",
            text: "I am proud of myself that I tried this.",
            author: "Sarah Sjöström",
            source: "World Aquatics — 2024 Year in Review",
            sourceURL: "https://www.worldaquatics.com/news/4192345/2024-year-in-review-swimmings-moment-in-the-spotlight"
        ),
        DailyHighlightQuote(
            id: "athlete-rudisha-mindset",
            text: "The mental approach to the sport is vital.",
            author: "David Rudisha",
            source: "World Athletics — Words of Wisdom: David Rudisha",
            sourceURL: "https://worldathletics.org/spikes/news/david-rudishas-words-of-wisdom"
        ),
        DailyHighlightQuote(
            id: "athlete-allen-work",
            text: "The secret is there is no secret.",
            author: "Ray Allen",
            source: "The Players’ Tribune — Letter to My Younger Self",
            sourceURL: "https://www.theplayerstribune.com/articles/ray-allen-letter-to-my-younger-self"
        ),
        DailyHighlightQuote(
            id: "athlete-jordan-trying",
            text: "I can’t accept not trying.",
            author: "Michael Jordan",
            source: "Chicago Sun-Times — Jordan: The stuff of an NBA legend (press-conference quotation)",
            sourceURL: "https://chicago.suntimes.com/bulls/2020/4/17/21223744/michael-jordan-the-stuff-of-an-nba-legend-last-dance"
        ),
        DailyHighlightQuote(
            id: "athlete-ronaldo-dream",
            text: "I started dreaming bigger and bigger.",
            author: "Cristiano Ronaldo",
            source: "The Players’ Tribune — Madrid: My Story",
            sourceURL: "https://www.theplayerstribune.com/articles/cristiano-ronaldo-madrid-english"
        ),
        DailyHighlightQuote(
            id: "athlete-alcaraz-belief",
            text: "I believe in myself all the time.",
            author: "Carlos Alcaraz",
            source: "ATP Tour — Alcaraz Masterclass Overwhelms Tsitsipas",
            sourceURL: "https://www.atptour.com/en/news/alcaraz-tsitsipas-roland-garros-2023-qf"
        ),
        DailyHighlightQuote(
            id: "athlete-djokovic-belief",
            text: "Believe in yourself. Every. Single. Day.",
            author: "Novak Djokovic",
            source: "Novak Djokovic — Official website, November 1, 2018",
            sourceURL: "https://novakdjokovic.com/tl/believe-in-yourself-every-single-day-%F0%9F%91%B6/"
        ),
        DailyHighlightQuote(
            id: "athlete-nadal-effort",
            text: "I always gave the maximum.",
            author: "Rafael Nadal",
            source: "The Players’ Tribune — The Gift",
            sourceURL: "https://projects.theplayerstribune.com/rafael-nadal-tennis"
        ),
        DailyHighlightQuote(
            id: "athlete-curry-ownership",
            text: "It’s no one’s story but mine.",
            author: "Stephen Curry",
            source: "The Players’ Tribune — Underrated",
            sourceURL: "https://www.theplayerstribune.com/articles/stephen-curry-underrated"
        ),
        DailyHighlightQuote(
            id: "athlete-brady-improvement",
            text: "The desire to get better never goes away.",
            author: "Tom Brady",
            source: "Tom Brady — No Days Off: Lesson #2 from a Lifetime of Leadership",
            sourceURL: "https://tombrady.com/posts/no-days-off-lesson-2-from-a-lifetime-of-leadership"
        )
    ]
}
