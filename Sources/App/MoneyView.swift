import SwiftUI

struct MoneyView: View {
    let data: FamilyData

    var body: some View {
        NavigationStack {
            List {
                switch data.money.value {
                case let .kid(_, kid):
                    kidSection(kid)
                case let .parent(_, kids):
                    ForEach(kids) { kidSection($0) }
                case .none:
                    EmptyView()
                }
                FreshnessLabel(fetchedAt: data.money.fetchedAt, error: data.money.error)
            }
            .navigationTitle(Text("Money"))
            .refreshable { await data.money.refresh() }
        }
    }

    private func kidSection(_ kid: KidMoney) -> some View {
        Section(kid.displayName) {
            HStack {
                Text("Balance")
                Spacer()
                Text(euros(kid.balanceCents)).monospacedDigit()
            }
            if !kid.hasAccounts {
                Text("No bank account linked yet").foregroundStyle(.secondary)
            }
            ForEach(kid.goals.filter { !$0.archived }) { goal in
                ProgressView(value: Double(goal.savedCents), total: Double(max(goal.targetCents, 1))) {
                    HStack {
                        Text(goal.title)
                        Spacer()
                        Text("\(euros(goal.savedCents)) / \(euros(goal.targetCents))").monospacedDigit()
                    }
                }
            }
        }
    }
}
