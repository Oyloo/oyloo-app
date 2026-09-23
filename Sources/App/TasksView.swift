import SwiftUI

struct TasksView: View {
    let data: FamilyData
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List {
                if let failure {
                    Text(failure).foregroundStyle(.red).font(.footnote)
                }
                ForEach(data.tasksToday.value?.todos ?? []) { task in
                    Button {
                        Task { await complete(task) }
                    } label: {
                        Label(task.title, systemImage: task.isOpen ? "circle" : "checkmark.circle.fill")
                    }
                    .disabled(!task.isOpen)
                }
                FreshnessLabel(fetchedAt: data.tasksToday.fetchedAt, error: data.tasksToday.error)
            }
            .navigationTitle(Text("Tasks"))
            .refreshable { await data.tasksToday.refresh() }
        }
    }

    /// Online only for now: a failed change says so and the task stays open.
    private func complete(_ task: TaskItem) async {
        do {
            try await AppAPI.completeTask(id: task.id)
            failure = nil
            await data.tasksToday.refresh()
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
