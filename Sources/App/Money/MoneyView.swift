import SwiftUI

/// The Money section: the child's own screen, or the parent's overview.
struct MoneyView: View {
    let data: FamilyData

    var body: some View {
        NavigationStack {
            Group {
                switch data.money.value {
                case let .kid(_, kid):
                    KidMoneyScreen(kid: kid, editable: true, data: data)
                case let .parent(_, kids, unassigned):
                    ParentMoneyScreen(kids: kids, unassigned: unassigned, data: data)
                        .navigationTitle(Text("Money"))
                case .none:
                    List { FreshnessLabel(fetchedAt: data.money.fetchedAt, error: data.money.error) }
                        .navigationTitle(Text("Money"))
                        .refreshable { await data.money.refresh() }
                }
            }
        }
    }
}
