import SwiftUI

struct TaskRow: View {
    let task: TaskItem
    let today: String
    let circle: String?
    let toggle: () async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await toggle() }
            } label: {
                Image(systemName: task.isOpen ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(task.isOpen ? Color.secondary : Color.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isOpen ? Text("Complete") : Text("Reopen"))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if task.important { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption) }
                    Text(task.title)
                        .strikethrough(!task.isOpen)
                        .foregroundStyle(task.isOpen ? .primary : .secondary)
                }
                let details = detailLine
                if !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary)
                }
                if let due = task.due, task.isOpen, let wording = DueWording.make(due: due, today: today) {
                    Text(dueText(wording)).font(.caption)
                        .foregroundStyle(wording.isOverdue ? Color.red : Color.secondary)
                }
            }
            Spacer(minLength: 0)
            if task.isOpen, task.priority == "P1" || task.priority == "P2" {
                Text(task.priority).font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(task.priority == "P1" ? Color.red.opacity(0.15) : Color.orange.opacity(0.15),
                                in: Capsule())
            }
        }
    }

    private var detailLine: String {
        var parts: [String] = []
        if let circle { parts.append(circle) }
        if let who = task.waitingOn, !who.isEmpty { parts.append(String(localized: "waiting on \(who)")) }
        parts += task.tags.map { "#\($0)" }
        return parts.joined(separator: " · ")
    }
}

extension DueWording {
    var isOverdue: Bool { if case .overdue = self { true } else { false } }
}
