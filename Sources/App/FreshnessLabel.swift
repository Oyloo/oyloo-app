import SwiftUI

/// "Updated 5 min ago" under a block; red with the reason when the last
/// refresh failed, so stale data is never mistaken for current.
struct FreshnessLabel: View {
    let fetchedAt: Date?
    let error: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 2) {
                if let fetchedAt {
                    Text(words(Freshness.of(fetchedAt, now: context.date)))
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .font(.caption2)
        }
    }

    private func words(_ f: Freshness) -> String {
        switch f {
        case .justNow: String(localized: "Updated just now")
        case .minutes(let n): String(localized: "Updated \(n) min ago")
        case .hours(let n): String(localized: "Updated \(n) h ago")
        case .days(let n): String(localized: "Updated \(n) d ago")
        }
    }
}

func euros(_ cents: Int) -> String {
    (Double(cents) / 100).formatted(.currency(code: "EUR"))
}
