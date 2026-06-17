import XCTest
import SwiftData
@testable import marble

final class SupplementTypeIconTests: MarbleTestCase {
    func testDisplayIconDefaultsToPillSymbol() {
        let type = SupplementType(name: "Creatine", unit: .g)
        XCTAssertEqual(type.displayIcon, .symbol(SupplementIcon.defaultSymbolName))
    }

    func testDisplayIconUsesCustomEmojiWhenPresent() {
        let type = SupplementType(name: "Protein Powder", unit: .scoop, customIconEmoji: "🥤")
        XCTAssertEqual(type.displayIcon, .emoji("🥤"))
    }

    func testInitializerSanitizesCustomEmojiToFirstValidEmoji() {
        let type = SupplementType(name: "Fish Oil", unit: .count, customIconEmoji: "Omega 🐟🔥")
        XCTAssertEqual(type.customIconEmoji, "🐟")
        XCTAssertEqual(type.displayIcon, .emoji("🐟"))
    }

    func testSetCustomIconEmojiClearsInvalidText() {
        let type = SupplementType(name: "Greens", unit: .scoop, customIconEmoji: "🌿")
        type.setCustomIconEmoji("not an emoji")
        XCTAssertNil(type.customIconEmoji)
        XCTAssertEqual(type.displayIcon, .symbol(SupplementIcon.defaultSymbolName))
    }

    func testSanitizedCustomIconHandlesLegacyUnsanitizedValues() {
        let type = SupplementType(name: "Caffeine", unit: .serving)
        type.customIconEmoji = "Morning ☕️ boost"
        XCTAssertEqual(type.sanitizedCustomIconEmoji, "☕️")
        XCTAssertEqual(type.displayIcon, .emoji("☕️"))
    }

    func testCustomEmojiPersistsAcrossSwiftDataSaveAndFetch() throws {
        let context = makeInMemoryContext()
        let type = SupplementType(name: "Electrolytes", unit: .scoop, customIconEmoji: "🧂")
        context.insert(type)
        try context.save()

        let fetched = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<SupplementType>(predicate: #Predicate { $0.name == "Electrolytes" })
            ).first
        )

        XCTAssertEqual(fetched.customIconEmoji, "🧂")
        XCTAssertEqual(fetched.displayIcon, .emoji("🧂"))
    }

    func testClearingCustomEmojiFallsBackToPillSymbolAfterSave() throws {
        let context = makeInMemoryContext()
        let type = SupplementType(name: "Vitamin C", unit: .count, customIconEmoji: "🍊")
        context.insert(type)
        try context.save()

        type.setCustomIconEmoji(nil)
        try context.save()

        let fetched = try XCTUnwrap(
            context.fetch(
                FetchDescriptor<SupplementType>(predicate: #Predicate { $0.name == "Vitamin C" })
            ).first
        )

        XCTAssertNil(fetched.customIconEmoji)
        XCTAssertEqual(fetched.displayIcon, .symbol(SupplementIcon.defaultSymbolName))
    }
}
