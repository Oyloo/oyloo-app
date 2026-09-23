import SwiftUI

struct TodayView: View {
    let data: FamilyData
    let open: (AppSection) -> Void

    private var summary: TodaySummary {
        TodaySummary.make(tasks: data.tasksToday.value, money: data.money.value)
    }

    var body: some View {
        NavigationStack {
            List {
                if data.sections.contains(.tasks) { tasksBlock }
                if data.sections.contains(.money) { moneyBlock }
                if data.sections.contains(.captures) { capturesBlock }
            }
            .navigationTitle(Text("Today"))
            .refreshable { await data.refreshAll() }
        }
    }

    private var tasksBlock: some View {
        Section {
            if summary.tasks.isEmpty {
                Text("Nothing due today").foregroundStyle(.secondary)
            }
            ForEach(summary.tasks) { task in
                Label(task.title, systemImage: task.overdue ? "exclamationmark.circle" : "circle")
            }
            if summary.openTaskCount > summary.tasks.count {
                Text("and \(summary.openTaskCount - summary.tasks.count) more").foregroundStyle(.secondary)
            }
            FreshnessLabel(fetchedAt: data.tasksToday.fetchedAt, error: data.tasksToday.error)
        } header: {
            Button { open(.tasks) } label: { Text("Tasks") }
        }
    }

    private var moneyBlock: some View {
        Section {
            ForEach(summary.money, id: \.name) { line in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(line.name)
                        Spacer()
                        Text(euros(line.balanceCents)).monospacedDigit()
                    }
                    if let goal = line.nextGoal {
                        ProgressView(value: Double(goal.savedCents), total: Double(max(goal.targetCents, 1))) {
                            Text(goal.title).font(.caption)
                        }
                    }
                }
            }
            FreshnessLabel(fetchedAt: data.money.fetchedAt, error: data.money.error)
        } header: {
            Button { open(.money) } label: { Text("Money") }
        }
    }

    private var capturesBlock: some View {
        Section {
            let recent = latest(data.captures.captures, count: 3, date: \.createdAt)
            if recent.isEmpty {
                Text("No captures yet").foregroundStyle(.secondary)
            }
            ForEach(recent) { capture in
                Text(capture.title ?? capture.vault).lineLimit(1)
            }
        } header: {
            Button { open(.captures) } label: { Text("Captures") }
        }
    }
}
