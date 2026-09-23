import SwiftUI

/// Task views with counts, a tag filter, status swipes and a new-task sheet.
struct TasksView: View {
    let data: FamilyData
    @State private var view: TaskView = .today
    @State private var tag: String?
    @State private var failure: String?
    @State private var adding = false

    private var resource: CachedResource<TasksOverview> { data.tasks(view: view, tag: tag) }

    var body: some View {
        let overview = resource.value
        NavigationStack {
            List {
                Section {
                    Picker("View", selection: $view) {
                        ForEach(TaskView.allCases) { v in
                            Text(viewLabel(v, count: data.tasksToday.value?.counts[v.rawValue]
                                           ?? overview?.counts[v.rawValue])).tag(v)
                        }
                    }
                    .pickerStyle(.menu)
                    if let tags = overview?.tags, !tags.isEmpty {
                        Picker("Tag", selection: $tag) {
                            Text("All tags").tag(String?.none)
                            ForEach(tags) { t in Text(t.label).tag(Optional(t.id)) }
                        }
                        .pickerStyle(.menu)
                    }
                }
                if let failure {
                    Text(failure).foregroundStyle(.red).font(.footnote)
                }
                Section {
                    let todos = overview?.todos ?? []
                    if todos.isEmpty, overview != nil {
                        Text("Nothing here.").foregroundStyle(.secondary)
                    }
                    ForEach(todos) { task in
                        TaskRow(task: task, today: overview?.today ?? "",
                                circle: overview?.circles.first { $0.id == task.circleId }?.label) {
                            await change(task, to: task.isOpen ? "done" : "next")
                        }
                        .swipeActions(edge: .trailing) {
                            ForEach(statusActions(for: task.status), id: \.self) { status in
                                Button(statusLabel(status)) { Task { await change(task, to: status) } }
                                    .tint(statusTint(status))
                            }
                        }
                    }
                }
                FreshnessLabel(fetchedAt: resource.fetchedAt, error: resource.error)
            }
            .navigationTitle(Text("Tasks"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = true } label: { Label("New task", systemImage: "plus") }
                }
            }
            .refreshable { await reload() }
            .task(id: "\(view.rawValue)|\(tag ?? "")") { await resource.refresh() }
            .sheet(isPresented: $adding) {
                NewTaskSheet(circles: overview?.circles ?? data.tasksToday.value?.circles ?? []) {
                    await reload()
                }
            }
        }
    }

    private func reload() async {
        await resource.refresh()
        if view != .today || tag != nil { await data.tasksToday.refresh() }
    }

    /// Online only: a failed change says so and the list stays as it was.
    private func change(_ task: TaskItem, to status: String) async {
        do {
            try await AppAPI.setTaskStatus(id: task.id, status: status)
            failure = nil
            await reload()
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
