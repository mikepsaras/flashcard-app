import Testing
import Foundation
@testable import Flashcards

@MainActor
@Suite struct DeckIconTests {
    @Test func euThemesLockColorButFlagsDoNot() {
        #expect(DeckIconPreset.isThemed(DeckIconPreset.euFlag))
        #expect(DeckIconPreset.isThemed(DeckIconPreset.euro))
        #expect(!DeckIconPreset.isThemed("theme.flag.de"))   // flags keep the deck's accent editable
        #expect(!DeckIconPreset.isThemed("book.fill"))
    }

    @Test func flagPrefixDoesNotCollideWithSymbols() {
        // The "flag.fill" SF Symbol must NOT be mistaken for a member-state flag preset.
        #expect(DeckIconPreset.isFlag("theme.flag.de"))
        #expect(!DeckIconPreset.isFlag("flag.fill"))
        #expect(DeckIconPreset.symbols.contains("flag.fill"))
    }

    @Test func allTwentySevenMemberStatesPresentAndWellFormed() {
        #expect(DeckIconPreset.flags.count == 27)
        let ids = DeckIconPreset.flags.map(\.id)
        #expect(Set(ids).count == 27)                                              // unique ids
        #expect(DeckIconPreset.flags.allSatisfy { $0.id.hasPrefix("theme.flag.") })
        #expect(DeckIconPreset.flags.allSatisfy { !$0.emoji.isEmpty && !$0.name.isEmpty })
        // Lookup + a couple of spot checks.
        #expect(DeckIconPreset.flag(for: "theme.flag.de")?.name == "Germany")
        #expect(DeckIconPreset.flag(for: "theme.flag.fr")?.emoji == "🇫🇷")
        #expect(DeckIconPreset.flag(for: "book.fill") == nil)
    }

    @Test func euroAndFlagIconsRoundTripThroughTheCodec() throws {
        let container = DeckStore.makeContainer()
        let euro = Deck(name: "Euro", colorHex: DeckIconPreset.euBlue, icon: DeckIconPreset.euro)
        let flag = Deck(name: "France", icon: "theme.flag.fr")
        container.mainContext.insert(euro)
        container.mainContext.insert(flag)

        // Bind the second container to a local so it outlives makeDeck + the property read.
        let other = DeckStore.makeContainer()
        let euroDTO = try DeckCodec.decodeDTO(DeckCodec.encode(euro))
        let flagDTO = try DeckCodec.decodeDTO(DeckCodec.encode(flag))
        #expect(DeckCodec.makeDeck(from: euroDTO, in: other.mainContext).icon == DeckIconPreset.euro)
        #expect(DeckCodec.makeDeck(from: flagDTO, in: other.mainContext).icon == "theme.flag.fr")
    }
}
