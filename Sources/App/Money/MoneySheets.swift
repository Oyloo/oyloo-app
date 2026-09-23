import SwiftUI

/// Sheets that collect an amount or a new goal. Each hands its action back
/// to the screen, which runs it and says whether it failed; the sheet
/// closes only on success so the typed values are not lost.
enum MoneySheet: Identifiable {
    case newGoal
    case move(MoneyGoal, out: Bool)

    var id: String {
        switch self {
        case .newGoal: "new"
        case let .move(goal, out): "move-\(goal.id)-\(out)"
        }
    }

    @MainActor @ViewBuilder
    func view(run: @escaping (@escaping () async throws -> Void) async -> String?) -> some View {
        switch self {
        case .newGoal: NewGoalSheet(run: run)
        case let .move(goal, out): MoveSheet(goal: goal, out: out, run: run)
        }
    }
}

struct NewGoalSheet: View {
    let run: (@escaping () async throws -> Void) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var target = ""
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("What are you saving for", text: $title)
                TextField("How much is needed, €", text: $target).keyboardType(.decimalPad)
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .navigationTitle(Text("New goal"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = title
                        let cents = parseEuroInput(target) ?? 0
                        Task {
                            failure = await run { try await AppAPI.createGoal(title: name, targetCents: cents) }
                            if failure == nil { dismiss() }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct MoveSheet: View {
    let goal: MoneyGoal
    let out: Bool
    let run: (@escaping () async throws -> Void) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(goal.title) {
                    TextField("Amount, €", text: $amount).keyboardType(.decimalPad)
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .navigationTitle(out ? Text("Take out") : Text("Put in"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cents = parseEuroInput(amount) ?? 0
                        let id = goal.id
                        let isOut = out
                        Task {
                            failure = await run { try await AppAPI.moveMoney(goalId: id, amountCents: cents, out: isOut) }
                            if failure == nil { dismiss() }
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
