import SwiftUI
import UIKit
import QuickLook

struct ContentView: View {
    @Bindable var vaultStore: VaultStore
    @State private var items: [SharedItem] = []
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TabView {
            ForEach(vaultStore.vaults) { vault in
                vaultTab(for: vault)
                    .tabItem { Label(vault.displayName, systemImage: vault.symbolName) }
            }
            VaultManagementView(store: vaultStore)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onAppear {
            vaultStore.reload()
            reload()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                vaultStore.reload()
                reload()
            }
        }
    }

    @ViewBuilder
    private func vaultTab(for vault: Vault) -> some View {
        let groups = groupedItems(for: vault.key)
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "No \(vault.displayName.lowercased()) shares yet",
                        systemImage: vault.symbolName,
                        description: Text("Share a URL, photo, file, or text from any app and pick \(vault.displayName) in the picker.")
                    )
                } else {
                    List {
                        ForEach(groups, id: \.day) { group in
                            Section(group.header) {
                                ForEach(group.items) { item in
                                    ItemRow(item: item)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                }
                                .onDelete { offsets in
                                    delete(from: group, offsets: offsets)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { reload() }
                }
            }
            .navigationTitle(vault.displayName)
            .toolbar {
                if !groups.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
            .background {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    MeshGradient(
                        width: 3, height: 3,
                        points: meshPoints(t: t),
                        colors: meshColors
                    )
                    .opacity(meshOpacity)
                    .ignoresSafeArea()
                }
            }
        }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let header: String
        let items: [SharedItem]
        var id: Date { day }
    }

    private func groupedItems(for vaultKey: String) -> [DayGroup] {
        let calendar = Calendar.current
        let sorted = items
            .filter { $0.vaultKey == vaultKey }
            .sorted(by: { $0.sharedAt > $1.sharedAt })
        let grouped = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.sharedAt) }
        return grouped.keys.sorted(by: >).map { day in
            DayGroup(day: day, header: dayHeader(for: day), items: grouped[day] ?? [])
        }
    }

    private func dayHeader(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func delete(from group: DayGroup, offsets: IndexSet) {
        let removed = offsets.map { group.items[$0] }
        for item in removed { SharedStore.deleteAttachment(of: item) }
        let removedIDs = Set(removed.map { $0.id })
        items.removeAll { removedIDs.contains($0.id) }
        SharedStore.replaceAll(items)
    }

    private func reload() {
        items = SharedStore.readAll()
    }

    private var meshColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.08, green: 0.05, blue: 0.22),
                Color(red: 0.18, green: 0.06, blue: 0.32),
                Color(red: 0.22, green: 0.06, blue: 0.28),
                Color(red: 0.05, green: 0.10, blue: 0.38),
                Color(red: 0.16, green: 0.16, blue: 0.45),
                Color(red: 0.32, green: 0.10, blue: 0.32),
                Color(red: 0.05, green: 0.22, blue: 0.32),
                Color(red: 0.10, green: 0.28, blue: 0.40),
                Color(red: 0.28, green: 0.22, blue: 0.10)
            ]
        }
        return [
            .indigo, .purple, .pink,
            .blue,   .cyan,   .orange,
            .teal,   .mint,   .yellow
        ]
    }

    private var meshOpacity: Double {
        colorScheme == .dark ? 0.85 : 0.45
    }

    private func meshPoints(t: TimeInterval) -> [SIMD2<Float>] {
        let s1 = Float(sin(t * 0.30) * 0.08)
        let s2 = Float(cos(t * 0.42) * 0.08)
        let s3 = Float(sin(t * 0.55) * 0.12)
        let s4 = Float(cos(t * 0.36) * 0.10)
        return [
            SIMD2<Float>(0,         0),
            SIMD2<Float>(0.5 + s1,  0),
            SIMD2<Float>(1,         0),
            SIMD2<Float>(0,         0.5 + s2),
            SIMD2<Float>(0.5 + s3,  0.5 + s4),
            SIMD2<Float>(1,         0.5 - s2),
            SIMD2<Float>(0,         1),
            SIMD2<Float>(0.5 - s1,  1),
            SIMD2<Float>(1,         1)
        ]
    }
}

private struct ItemRow: View {
    let item: SharedItem
    @State private var quickLookURL: URL?

    private var attachmentFileURL: URL? {
        guard let path = item.attachmentPath else { return nil }
        return SharedStore.resolveAttachment(path)
    }

    var body: some View {
        Group {
            if item.attachmentPath != nil {
                Button { quickLookURL = attachmentFileURL } label: { rowContent }
            } else if item.isLink, let url = URL(string: item.url ?? "") {
                Link(destination: url) { rowContent }
            } else {
                rowContent
            }
        }
        .buttonStyle(.plain)
        .contextMenu { menuContent }
        .quickLookPreview($quickLookURL)
    }

    @ViewBuilder
    private var menuContent: some View {
        if let urlString = item.url {
            Button {
                UIPasteboard.general.string = urlString
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }
            if let url = URL(string: urlString) {
                ShareLink(item: url)
            }
        }
        if let text = item.text {
            Button {
                UIPasteboard.general.string = text
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }
        if let path = item.attachmentPath, let fileURL = SharedStore.resolveAttachment(path) {
            ShareLink(item: fileURL)
        }
    }

    private var rowContent: some View {
        Group {
            if item.isImage {
                imageHeroLayout
            } else {
                standardLayout
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var imageHeroLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let path = item.attachmentPath,
               let url = SharedStore.resolveAttachment(path),
               let img = UIImage(contentsOfFile: url.path) {
                GeometryReader { geo in
                    ZStack {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .blur(radius: 24)
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            if let title = item.title, !title.isEmpty {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Text(item.sharedAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var standardLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            leadingIcon
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                if let title = item.title, !title.isEmpty {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                bodyContent
                Text(item.sharedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if item.isImage,
           let path = item.attachmentPath,
           let url = SharedStore.resolveAttachment(path),
           let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else if item.isFile {
            Image(systemName: fileSystemIcon(for: item.mimeType))
                .font(.title2)
                .foregroundStyle(.secondary)
        } else if item.isText {
            Image(systemName: "quote.opening")
                .font(.title2)
                .foregroundStyle(.secondary)
        } else if let urlString = item.url,
                  let host = URL(string: urlString)?.host,
                  let favURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") {
            AsyncImage(url: favURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    Image(systemName: "globe").foregroundStyle(.secondary)
                }
            }
        } else {
            Image(systemName: "globe").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let text = item.text {
            Text(text)
                .font(.footnote)
                .italic()
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
        if let urlString = item.url {
            Text(urlString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        if item.isFile, let mime = item.mimeType {
            Text(mime)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func fileSystemIcon(for mime: String?) -> String {
        guard let mime = mime else { return "doc" }
        if mime.contains("pdf") { return "doc.richtext" }
        if mime.contains("zip") || mime.contains("compressed") { return "doc.zipper" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime.contains("word") || mime.contains("document") { return "doc.text" }
        if mime.contains("sheet") || mime.contains("excel") { return "tablecells" }
        return "doc"
    }
}

#Preview {
    ContentView(vaultStore: VaultStore())
}
