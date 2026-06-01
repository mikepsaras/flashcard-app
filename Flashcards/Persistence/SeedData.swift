import Foundation
import SwiftData

/// Seeds a couple of sample decks on first launch so the app is never empty.
enum SeedData {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Deck>())) ?? 0
        guard existing == 0 else { return }

        for spec in specs {
            let deck = Deck(name: spec.name, deckDescription: spec.description, colorHex: spec.colorHex, backLabel: spec.backLabel)
            context.insert(deck)
            for pair in spec.cards {
                context.insert(Card(term: pair.0, definition: pair.1, deck: deck))
            }
        }
        try? context.save()
    }

    private struct DeckSpec {
        let name: String
        let description: String
        let colorHex: String
        var backLabel: String = "Definition"
        let cards: [(String, String)]
    }

    private static let specs: [DeckSpec] = [
        DeckSpec(
            name: "Project Management & Agile",
            description: "Core Agile, Scrum & Kanban concepts",
            colorHex: "#3478F6",
            cards: [
                ("User Stories", "Short, simple descriptions of a feature told from the user's perspective — \"As a <role>, I want <goal> so that <benefit>.\""),
                ("Sprint", "A fixed-length time-box (usually 1–4 weeks) in which a Scrum team completes a set amount of work."),
                ("Scrum", "An Agile framework built around fixed-length sprints, defined roles, and regular ceremonies for inspecting and adapting."),
                ("Kanban", "A pull-based method that visualizes work on a board and limits work-in-progress to improve flow."),
                ("Product Backlog", "An ordered, ever-evolving list of everything that might be needed in the product, owned by the Product Owner."),
                ("Velocity", "A measure of how much work a team completes in a sprint, used to forecast future capacity."),
                ("Definition of Done", "A shared, explicit checklist of criteria a work item must meet to be considered complete."),
                ("Retrospective", "A ceremony at the end of a sprint where the team reflects on how to improve its process."),
                ("Story Points", "A relative unit for estimating the effort of a backlog item, accounting for complexity and uncertainty."),
                ("Daily Standup", "A short daily meeting where the team syncs on progress, plans, and blockers."),
                ("Epic", "A large body of work that can be broken down into multiple user stories."),
                ("Burndown Chart", "A graph showing remaining work over time, used to track sprint or release progress."),
            ]
        ),
        DeckSpec(
            name: "Capital Cities",
            description: "World capitals to memorize",
            colorHex: "#34C759",
            backLabel: "Capital",
            cards: [
                ("Japan", "Tokyo"),
                ("Australia", "Canberra"),
                ("Canada", "Ottawa"),
                ("Brazil", "Brasília"),
                ("Egypt", "Cairo"),
                ("Norway", "Oslo"),
                ("Kenya", "Nairobi"),
                ("Switzerland", "Bern"),
                ("New Zealand", "Wellington"),
                ("Turkey", "Ankara"),
            ]
        ),
    ]
}
