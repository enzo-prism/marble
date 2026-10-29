import Foundation

/// Second Daily Highlights quote catalog: validated public-domain quotes
/// merged from the ancient / modern-classics / american collector batches.
///
/// Each entry is 140 characters or fewer, carries a pre-1930 primary-source
/// citation, and is unique by text — both within this file and against the
/// original 45 bundled quotes (the 6 batch entries duplicating bundled texts
/// were dropped here, keeping the originals). Audit follow-up also drops
/// q123 (Roosevelt "dare mighty things" truncated mid-clause; the complete
/// sentence exceeds 140 chars), q147 (near-duplicate of bundled
/// `alcott-learning-to-sail` modulo contractions), and q148 (truncated
/// prefix of bundled `bronte-independent-will`), keeping the bundled
/// originals; q121/q126/q127 were replaced in place with complete verbatim
/// PD texts (Aesop Townsend moral, full Emerson sentence, complete Thoreau
/// sentence). No author appears more than three times.
enum DailyHighlightQuoteExtension {
    static let quotes: [DailyHighlightQuote] = [
        DailyHighlightQuote(
            id: "q101",
            text: "The impediment to action advances action. What stands in the way becomes the way.",
            author: "Marcus Aurelius",
            source: "Meditations, Book 5",
            sourceURL: "https://www.gutenberg.org/ebooks/15877"
        ),
        DailyHighlightQuote(
            id: "q102",
            text: "Waste no more time arguing about what a good man should be. Be one.",
            author: "Marcus Aurelius",
            source: "Meditations, Book 10",
            sourceURL: "https://www.gutenberg.org/ebooks/15877"
        ),
        DailyHighlightQuote(
            id: "q103",
            text: "Very little is needed to make a happy life; it is all within yourself.",
            author: "Marcus Aurelius",
            source: "Meditations, Book 7",
            sourceURL: "https://www.gutenberg.org/ebooks/15877"
        ),
        DailyHighlightQuote(
            id: "q104",
            text: "Men are disturbed, not by things, but by the principles and notions which they form concerning things.",
            author: "Epictetus",
            source: "Enchiridion, 5",
            sourceURL: "https://classics.mit.edu/Epictetus/epicench.html"
        ),
        DailyHighlightQuote(
            id: "q105",
            text: "Demand not that events should happen as you wish; but wish them to happen as they do happen, and you will go on well.",
            author: "Epictetus",
            source: "Enchiridion, 8",
            sourceURL: "https://www.gutenberg.org/ebooks/10661"
        ),
        DailyHighlightQuote(
            id: "q106",
            text: "Practice yourself, for heaven's sake, in little things, and thence proceed to greater.",
            author: "Epictetus",
            source: "Discourses, Book 1",
            sourceURL: "https://www.gutenberg.org/ebooks/45109"
        ),
        DailyHighlightQuote(
            id: "q107",
            text: "It is not because things are difficult that we do not dare; it is because we do not dare that they are difficult.",
            author: "Seneca",
            source: "Moral Letters to Lucilius, Letter 104",
            sourceURL: "https://en.wikisource.org/wiki/Moral_letters_to_Lucilius"
        ),
        DailyHighlightQuote(
            id: "q108",
            text: "Begin at once to live, and count each separate day as a separate life.",
            author: "Seneca",
            source: "Moral Letters to Lucilius, Letter 101",
            sourceURL: "https://en.wikisource.org/wiki/Moral_letters_to_Lucilius"
        ),
        DailyHighlightQuote(
            id: "q109",
            text: "While we are postponing, life speeds by.",
            author: "Seneca",
            source: "Moral Letters to Lucilius, Letter 1",
            sourceURL: "https://en.wikisource.org/wiki/Moral_letters_to_Lucilius"
        ),
        DailyHighlightQuote(
            id: "q110",
            text: "Man is by nature a social animal.",
            author: "Aristotle",
            source: "Politics, Book 1",
            sourceURL: "https://classics.mit.edu/Aristotle/politics.html"
        ),
        DailyHighlightQuote(
            id: "q111",
            text: "Virtue lies in our power, and similarly so does vice.",
            author: "Aristotle",
            source: "Nicomachean Ethics, Book 3",
            sourceURL: "https://www.gutenberg.org/ebooks/8438"
        ),
        DailyHighlightQuote(
            id: "q112",
            text: "Happiness depends upon ourselves.",
            author: "Aristotle",
            source: "Nicomachean Ethics, Book 1",
            sourceURL: "https://www.gutenberg.org/ebooks/8438"
        ),
        DailyHighlightQuote(
            id: "q113",
            text: "To see what is right and not to do it is want of courage.",
            author: "Confucius",
            source: "Analects, 2.24",
            sourceURL: "https://www.gutenberg.org/ebooks/4094"
        ),
        DailyHighlightQuote(
            id: "q114",
            text: "The superior man is modest in his speech, but exceeds in his actions.",
            author: "Confucius",
            source: "Analects, 14.27",
            sourceURL: "https://www.gutenberg.org/ebooks/4094"
        ),
        DailyHighlightQuote(
            id: "q115",
            text: "What you do not want done to yourself, do not do to others.",
            author: "Confucius",
            source: "Analects, 15.24",
            sourceURL: "https://www.gutenberg.org/ebooks/4094"
        ),
        DailyHighlightQuote(
            id: "q116",
            text: "A journey of a thousand li commences with a single step.",
            author: "Laozi",
            source: "Tao Te Ching, ch. 64",
            sourceURL: "https://www.gutenberg.org/ebooks/216"
        ),
        DailyHighlightQuote(
            id: "q117",
            text: "He who knows others is wise; he who knows himself is enlightened.",
            author: "Laozi",
            source: "Tao Te Ching, ch. 33",
            sourceURL: "https://www.gutenberg.org/ebooks/216"
        ),
        DailyHighlightQuote(
            id: "q118",
            text: "The unexamined life is not worth living.",
            author: "Socrates",
            source: "Plato, Apology 38a",
            sourceURL: "https://classics.mit.edu/Plato/apology.html"
        ),
        DailyHighlightQuote(
            id: "q119",
            text: "The beginning is the most important part of the work.",
            author: "Plato",
            source: "Republic",
            sourceURL: "https://classics.mit.edu/Plato/republic.html"
        ),
        DailyHighlightQuote(
            id: "q120",
            text: "No man ever steps in the same river twice.",
            author: "Heraclitus",
            source: "Fragments, via Plato, Cratylus 402a",
            sourceURL: "https://classics.mit.edu/Plato/cratylus.html"
        ),
        DailyHighlightQuote(
            id: "q121",
            text: "United we stand, divided we fall.",
            author: "Aesop",
            source: "Aesop's Fables — 'The Four Oxen and the Lion' (George Fyler Townsend trans., 1867)",
            sourceURL: "https://www.gutenberg.org/ebooks/28"
        ),
        DailyHighlightQuote(
            id: "q122",
            text: "If you know the enemy and know yourself, you need not fear the result of a hundred battles.",
            author: "Sun Tzu",
            source: "The Art of War, ch. 3",
            sourceURL: "https://www.gutenberg.org/ebooks/132"
        ),
        DailyHighlightQuote(
            id: "q124",
            text: "I wish to preach, not the doctrine of ignoble ease, but the doctrine of the strenuous life.",
            author: "Theodore Roosevelt",
            source: "The Strenuous Life, speech at Chicago, 10 April 1899",
            sourceURL: "https://en.wikisource.org/wiki/The_Strenuous_Life"
        ),
        DailyHighlightQuote(
            id: "q126",
            text: "A foolish consistency is the hobgoblin of little minds, adored by little statesmen and philosophers and divines.",
            author: "Ralph Waldo Emerson",
            source: "Essays: First Series — 'Self-Reliance' (1841)",
            sourceURL: "https://www.gutenberg.org/ebooks/2944"
        ),
        DailyHighlightQuote(
            id: "q127",
            text: "The mass of men lead lives of quiet desperation.",
            author: "Henry David Thoreau",
            source: "Walden (1854)",
            sourceURL: "https://www.gutenberg.org/ebooks/205"
        ),
        DailyHighlightQuote(
            id: "q128",
            text: "You have seen how a man was made a slave; you shall see how a slave was made a man.",
            author: "Frederick Douglass",
            source: "Narrative of the Life of Frederick Douglass (1845)",
            sourceURL: "https://www.gutenberg.org/ebooks/23"
        ),
        DailyHighlightQuote(
            id: "q129",
            text: "Success is to be measured not so much by the position that one has reached in life as by the obstacles which he has overcome.",
            author: "Booker T. Washington",
            source: "Up from Slavery (1901)",
            sourceURL: "https://www.gutenberg.org/ebooks/2376"
        ),
        DailyHighlightQuote(
            id: "q130",
            text: "No race can prosper till it learns that there is as much dignity in tilling a field as in writing a poem.",
            author: "Booker T. Washington",
            source: "Up from Slavery (1901)",
            sourceURL: "https://www.gutenberg.org/ebooks/2376"
        ),
        DailyHighlightQuote(
            id: "q131",
            text: "As a man thinketh in his heart so is he.",
            author: "James Allen",
            source: "As a Man Thinketh (1903)",
            sourceURL: "https://www.gutenberg.org/ebooks/4507"
        ),
        DailyHighlightQuote(
            id: "q132",
            text: "Man is made or unmade by himself.",
            author: "James Allen",
            source: "As a Man Thinketh (1903)",
            sourceURL: "https://www.gutenberg.org/ebooks/4507"
        ),
        DailyHighlightQuote(
            id: "q134",
            text: "Heaven helps those who help themselves.",
            author: "Samuel Smiles",
            source: "Self-Help (1859)",
            sourceURL: "https://www.gutenberg.org/ebooks/935"
        ),
        DailyHighlightQuote(
            id: "q135",
            text: "The battle of life is, in most cases, fought uphill.",
            author: "Samuel Smiles",
            source: "Self-Help (1859)",
            sourceURL: "https://www.gutenberg.org/ebooks/935"
        ),
        DailyHighlightQuote(
            id: "q136",
            text: "Courage is resistance to fear, mastery of fear, not absence of fear.",
            author: "Mark Twain",
            source: "The Tragedy of Pudd'nhead Wilson (1894) — 'Pudd'nhead Wilson's Calendar'",
            sourceURL: "https://www.gutenberg.org/ebooks/102"
        ),
        DailyHighlightQuote(
            id: "q137",
            text: "Travel is fatal to prejudice, bigotry, and narrow-mindedness.",
            author: "Mark Twain",
            source: "Following the Equator (1897), Conclusion",
            sourceURL: "https://www.gutenberg.org/ebooks/2895"
        ),
        DailyHighlightQuote(
            id: "q138",
            text: "As to the Adjective: when in doubt, strike it out.",
            author: "Mark Twain",
            source: "The Tragedy of Pudd'nhead Wilson (1894) — 'Pudd'nhead Wilson's Calendar'",
            sourceURL: "https://www.gutenberg.org/ebooks/102"
        ),
        DailyHighlightQuote(
            id: "q139",
            text: "With malice toward none; with charity for all.",
            author: "Abraham Lincoln",
            source: "Second Inaugural Address, 4 March 1865",
            sourceURL: "https://en.wikisource.org/wiki/Lincoln%27s_Second_Inaugural_Address"
        ),
        DailyHighlightQuote(
            id: "q140",
            text: "Let us strive on to finish the work we are in.",
            author: "Abraham Lincoln",
            source: "Second Inaugural Address (1865)",
            sourceURL: "https://en.wikisource.org/wiki/Abraham_Lincoln%27s_Second_Inaugural_Address"
        ),
        DailyHighlightQuote(
            id: "q141",
            text: "He who climbeth on the highest mountains, laugheth at all tragic plays and tragic realities.",
            author: "Friedrich Nietzsche",
            source: "Thus Spake Zarathustra (1883-1885; Thomas Common trans., 1909)",
            sourceURL: "https://www.gutenberg.org/ebooks/1998"
        ),
        DailyHighlightQuote(
            id: "q142",
            text: "Man is something that is to be surpassed.",
            author: "Friedrich Nietzsche",
            source: "Thus Spake Zarathustra (1883-1885; Thomas Common trans., 1909)",
            sourceURL: "https://www.gutenberg.org/ebooks/1998"
        ),
        DailyHighlightQuote(
            id: "q143",
            text: "If you can meet with Triumph and Disaster and treat those two impostors just the same.",
            author: "Rudyard Kipling",
            source: "Rewards and Fairies (1910) — 'If—'",
            sourceURL: "https://www.gutenberg.org/ebooks/556"
        ),
        DailyHighlightQuote(
            id: "q144",
            text: "If you can fill the unforgiving minute with sixty seconds' worth of distance run.",
            author: "Rudyard Kipling",
            source: "Rewards and Fairies (1910) — 'If—'",
            sourceURL: "https://www.gutenberg.org/ebooks/556"
        ),
        DailyHighlightQuote(
            id: "q145",
            text: "The man who dies thus rich dies disgraced.",
            author: "Andrew Carnegie",
            source: "The Gospel of Wealth (1889)",
            sourceURL: "https://en.wikisource.org/wiki/The_Gospel_of_Wealth"
        ),
        DailyHighlightQuote(
            id: "q146",
            text: "If you work for a man, in heaven's name work for him.",
            author: "Elbert Hubbard",
            source: "A Message to Garcia (1899)",
            sourceURL: "https://en.wikisource.org/wiki/A_Message_to_Garcia"
        ),
        DailyHighlightQuote(
            id: "q149",
            text: "Discipline is the soul of an army.",
            author: "George Washington",
            source: "Letter of Instructions to the Captains of the Virginia Regiments, 29 July 1759",
            sourceURL: "https://founders.archives.gov/?q=%22Discipline%20is%20the%20soul%20of%20an%20army%22"
        ),
        DailyHighlightQuote(
            id: "q150",
            text: "Perseverance and Spirit have done Wonders in all ages.",
            author: "George Washington",
            source: "Letter to Major General Philip Schuyler, 20 August 1775",
            sourceURL: "https://founders.archives.gov/documents/Washington/03-01-02-0233"
        ),
        DailyHighlightQuote(
            id: "q151",
            text: "Honesty is the first chapter in the book of wisdom.",
            author: "Thomas Jefferson",
            source: "Letter to Nathaniel Macon, 12 January 1819",
            sourceURL: "https://founders.archives.gov/?q=%22Honesty%20is%20the%20first%20chapter%20in%20the%20book%20of%20wisdom%22"
        ),
        DailyHighlightQuote(
            id: "q153",
            text: "Diligence is the mother of good luck.",
            author: "Benjamin Franklin",
            source: "Poor Richard's Almanack, 1736",
            sourceURL: "https://www.gutenberg.org/files/25534/25534-h/25534-h.htm"
        ),
        DailyHighlightQuote(
            id: "q154",
            text: "Facts are stubborn things.",
            author: "John Adams",
            source: "Argument in defense of the British soldiers, Boston Massacre trial, December 1770",
            sourceURL: "https://founders.archives.gov/?q=%22Facts%20are%20stubborn%20things%22"
        ),
        DailyHighlightQuote(
            id: "q155",
            text: "The harder the conflict, the more glorious the triumph.",
            author: "Thomas Paine",
            source: "The American Crisis No. 1, 23 December 1776",
            sourceURL: "https://www.gutenberg.org/files/3741/3741-h/3741-h.htm"
        ),
        DailyHighlightQuote(
            id: "q156",
            text: "These are the times that try men's souls.",
            author: "Thomas Paine",
            source: "The American Crisis No. 1, 23 December 1776",
            sourceURL: "https://www.gutenberg.org/files/3741/3741-h/3741-h.htm"
        ),
        DailyHighlightQuote(
            id: "q157",
            text: "Give me liberty, or give me death!",
            author: "Patrick Henry",
            source: "Speech to the Second Virginia Convention, Richmond, 23 March 1775",
            sourceURL: "https://avalon.law.yale.edu/18th_century/patrick.asp"
        ),
        DailyHighlightQuote(
            id: "q161",
            text: "Nothing great was ever achieved without enthusiasm.",
            author: "Ralph Waldo Emerson",
            source: "Circles, Essays (1841)",
            sourceURL: "https://www.gutenberg.org/files/16643/16643-h/16643-h.htm"
        ),
        DailyHighlightQuote(
            id: "q162",
            text: "I know of no more encouraging fact than the unquestionable ability of man to elevate his life by a conscious endeavor.",
            author: "Henry David Thoreau",
            source: "Walden; or, Life in the Woods (1854), 'Where I Lived, and What I Lived For'",
            sourceURL: "https://www.gutenberg.org/files/205/205-h/205-h.htm"
        ),
        DailyHighlightQuote(
            id: "q163",
            text: "If you have built castles in the air, your work need not be lost.",
            author: "Henry David Thoreau",
            source: "Walden; or, Life in the Woods (1854), 'Conclusion'",
            sourceURL: "https://www.gutenberg.org/files/205/205-h/205-h.htm"
        ),
        DailyHighlightQuote(
            id: "q164",
            text: "Let us, then, be up and doing, with a heart for any fate.",
            author: "Henry Wadsworth Longfellow",
            source: "A Psalm of Life (1838)",
            sourceURL: "https://en.wikisource.org/wiki/A_Psalm_of_Life"
        ),
        DailyHighlightQuote(
            id: "q165",
            text: "I have not yet begun to fight.",
            author: "John Paul Jones",
            source: "Reply when called on to surrender, Bonhomme Richard vs. Serapis, 23 September 1779",
            sourceURL: "https://www.navy.mil/Press-Office/News-Stories/Article/2249402/john-paul-jones-the-man-of-wars/"
        ),
        DailyHighlightQuote(
            id: "q166",
            text: "Damn the torpedoes! Full speed ahead!",
            author: "David Glasgow Farragut",
            source: "Order at the Battle of Mobile Bay, 5 August 1864",
            sourceURL: "https://www.loc.gov/item/today-in-history/august-23/"
        ),
        DailyHighlightQuote(
            id: "q167",
            text: "No terms except an unconditional and immediate surrender can be accepted.",
            author: "Ulysses S. Grant",
            source: "Reply to General Simon B. Buckner, Fort Donelson, 16 February 1862; in Personal Memoirs of U. S. Grant (1885)",
            sourceURL: "https://www.gutenberg.org/files/5861/5861-h/5861-h.htm"
        ),
        DailyHighlightQuote(
            id: "q168",
            text: "The credit belongs to the man who is actually in the arena.",
            author: "Theodore Roosevelt",
            source: "Citizenship in a Republic, Sorbonne, Paris, 23 April 1910",
            sourceURL: "https://en.wikisource.org/wiki/Citizenship_in_a_Republic"
        ),
        DailyHighlightQuote(
            id: "q169",
            text: "Failure is impossible.",
            author: "Susan B. Anthony",
            source: "Last public address, Baltimore, February 1906",
            sourceURL: "https://www.loc.gov/item/rbcmiller002848"
        ),
        DailyHighlightQuote(
            id: "q170",
            text: "It is in the pinch that the pitcher shows whether or not he is a Big Leaguer.",
            author: "Christy Mathewson",
            source: "Pitching in a Pinch; or, Baseball from the Inside (1912)",
            sourceURL: "https://www.gutenberg.org/files/33291/33291-h/33291-h.htm"
        )
    ]
}
