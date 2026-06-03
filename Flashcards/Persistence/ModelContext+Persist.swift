import Foundation
import SwiftData

@MainActor
extension ModelContext {
    /// The standard mutation tail: stamp `modifiedAt` on the decks a change touched, save the
    /// in-memory context, then write the library to disk via `DeckStore.persist`. Collapses the
    /// `deck.modifiedAt = .now; try? save(); DeckStore.persist(context)` ritual the views would
    /// otherwise repeat — and occasionally get subtly wrong — at every call site.
    func saveAndPersist(touching decks: Deck...) {
        let now = Date.now
        for deck in decks { deck.modifiedAt = now }
        try? save()
        DeckStore.persist(self)
    }
}
