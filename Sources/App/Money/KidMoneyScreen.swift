import SwiftUI

/// One child's money. Editable for the child themself; read-only when a
/// parent opens it, because the server only lets a child change their goals.
struct KidMoneyScreen: View {
    let kid: KidMoney
    let editable: Bool
    let data: FamilyData

    @State private var sheet: MoneySheet?
    @State private var showArchived = false
    @State private var failure: String?

    var body: some View {
        List {
            if let failure {
                Text(failure).foregroundStyle(.red).font(.footnote)
            }
            ForEach(Array(moneyWarnings(for: kid).enumerated()), id: \.offset) { _, warning in
                Label(warningText(warning), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
            }
            if kid.hasAccounts {
                header
                goals
                places
                feed
            }
            FreshnessLabel(fetchedAt: data.money.fetchedAt, error: data.money.error)
        }
        .navigationTitle(kid.displayName)
        .refreshable { await data.money.refresh() }
        .sheet(item: $sheet) { sheet in
            sheet.view { action in await run(action) }
        }
    }

    private var header: some View {
        Section {
            LabeledContent("Balance") {
                VStack(alignment: .trailing) {
                    Text(euros(kid.balanceCents)).font(.title2.bold()).monospacedDigit()
                    if let asOf = kid.balanceAsOf {
                        Text("per the bank on \(asOf)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Free") { Text(euros(kid.freeCents)).monospacedDigit() }
            LabeledContent("Set aside for goals") { Text(euros(kid.reservedCents)).monospacedDigit() }
            if let month = kid.month {
                LabeledContent("Received this month") {
                    Text("+\(euros(month.receivedCents))").monospacedDigit().foregroundStyle(.green)
                }
                LabeledContent("Spent this month") {
                    Text("−\(euros(month.spentCents))").monospacedDigit()
                }
            }
        }
    }

    private var goals: some View {
        let groups = goalGroups(kid.goals)
        return Section {
            if groups.active.isEmpty {
                Text("No goals yet. What are you saving for?").foregroundStyle(.secondary)
            }
            ForEach(groups.active) { goal in goalRow(goal) }
            if editable {
                Button { sheet = .newGoal } label: { Label("New goal", systemImage: "plus") }
            }
            if !groups.archived.isEmpty {
                DisclosureGroup(isExpanded: $showArchived) {
                    ForEach(groups.archived) { goal in goalRow(goal) }
                } label: {
                    Text("Archive (\(groups.archived.count))")
                }
            }
        } header: {
            Text("Goals")
        }
    }

    private func goalRow(_ goal: MoneyGoal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(goal.title)
                if goal.achieved { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                Spacer()
                Text("\(euros(goal.savedCents)) / \(euros(goal.targetCents))").monospacedDigit().font(.callout)
            }
            ProgressView(value: Double(min(goal.savedCents, goal.targetCents)), total: Double(max(goal.targetCents, 1)))
            if editable {
                HStack {
                    if goal.archived {
                        Button("Restore") { Task { await run { try await AppAPI.unarchiveGoal(id: goal.id) } } }
                    } else {
                        Button("Put in") { sheet = .move(goal, out: false) }
                        Button("Take out") { sheet = .move(goal, out: true) }
                        Spacer()
                        Button("Archive", role: .destructive) {
                            Task { await run { try await AppAPI.archiveGoal(id: goal.id) } }
                        }
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var places: some View {
        if !kid.places.isEmpty {
            Section("Where the money goes") {
                ForEach(kid.places, id: \.name) { place in
                    LabeledContent(place.name) {
                        Text("\(euros(place.cents)) · \(place.count)").monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder private var feed: some View {
        if !kid.feed.isEmpty {
            Section("Recent operations") {
                ForEach(Array(kid.feed.enumerated()), id: \.offset) { _, item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.label).lineLimit(1)
                            Text(item.date).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(euros(item.amountCents)).monospacedDigit()
                            .foregroundStyle(item.kind == "in" ? .green : .primary)
                    }
                }
            }
        }
    }

    /// Online only: a refusal is shown here and nothing else changes.
    private func run(_ action: @escaping () async throws -> Void) async -> String? {
        do {
            try await action()
            failure = nil
            await data.money.refresh()
            return nil
        } catch {
            let text = moneyFailureText(error)
            failure = text
            return text
        }
    }
}
