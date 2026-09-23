import SwiftUI

/// A new task: dictate a phrase with the keyboard's microphone, tap Parse,
/// check what came out, then Add. Nothing is saved before Add.
struct NewTaskSheet: View {
    let circles: [TaskCircle]
    let added: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var phrase = ""
    @State private var draft = TaskDraft(title: "", due: nil, important: false, circleId: nil, tags: [])
    @State private var hasDue = false
    @State private var dueDate = Date()
    @State private var parsing = false
    @State private var saving = false
    @State private var note: String?
    @FocusState private var phraseFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Say or type the task", text: $phrase, axis: .vertical)
                        .focused($phraseFocused)
                        .lineLimit(1...4)
                    Button {
                        Task { await parse() }
                    } label: {
                        if parsing { ProgressView() } else { Label("Parse", systemImage: "sparkles") }
                    }
                    .disabled(phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsing)
                } footer: {
                    Text("Tap the microphone on the keyboard to dictate. Parsing sends the phrase to the server and OpenAI.")
                }
                if let note { Text(note).font(.footnote).foregroundStyle(.orange) }
                Section {
                    TextField("Title", text: $draft.title, axis: .vertical)
                    Toggle("Due date", isOn: $hasDue)
                    if hasDue {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                    Toggle("Important", isOn: $draft.important)
                    if !circles.isEmpty {
                        Picker("Circle", selection: $draft.circleId) {
                            Text("Only me").tag(String?.none)
                            ForEach(circles) { c in Text(c.label).tag(Optional(c.id)) }
                        }
                    }
                    if !draft.tags.isEmpty {
                        Text(draft.tags.map { "#\($0)" }.joined(separator: " "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(Text("New task"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
            .onAppear { phraseFocused = true }
        }
    }

    private func parse() async {
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        parsing = true
        defer { parsing = false }
        do {
            apply(try await AppAPI.parseTask(text: text))
            note = nil
        } catch {
            if draft.title.isEmpty { draft.title = text }
            note = parseFailureText(error)
        }
    }

    private func apply(_ parsed: TaskDraft) {
        draft.title = parsed.title
        draft.important = parsed.important
        draft.tags = parsed.tags
        draft.circleId = circles.contains { $0.id == parsed.circleId } ? parsed.circleId : nil
        if let due = parsed.due, let date = DueWording.day(due) {
            hasDue = true
            dueDate = date
        } else {
            hasDue = false
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body = draft
        body.due = hasDue ? isoDay(dueDate) : nil
        do {
            try await AppAPI.createTask(body)
            await added()
            dismiss()
        } catch {
            note = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// The picker works in local time; the server wants the calendar day.
    private func isoDay(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
