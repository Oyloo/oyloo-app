import SwiftUI
import UIKit
import QuickLook

struct ContentView: View {
    @Bindable var vaultStore: VaultStore
    @State private var items: [SharedItem] = []
    /// Captures the server holds. Without an App Group the share extension
    /// uploads on its own and its files never reach this process, so the
    /// server's list is the only complete history of what was shared.
    @State private var feed = CaptureFeed()
    @State private var selectedVaultKey: String?
    @State private var settingsSelected = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height && geometry.size.width >= 640
            Group {
                if landscape {
                    landscapeShell
                } else {
                    portraitTabs
                }
            }
        }
        .onAppear {
            vaultStore.reload()
            ensureSelection()
            reload()
        }
        .task { await feed.refresh() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                vaultStore.reload()
                ensureSelection()
                reload()
                Task { await feed.refresh() }
            }
        }
        .onChange(of: vaultStore.vaults.map(\.key)) { _, _ in
            ensureSelection()
        }
    }

    private var portraitTabs: some View {
        TabView {
            ForEach(vaultStore.vaults) { vault in
                vaultTab(for: vault)
                    .tabItem { Label(vault.displayName, systemImage: vault.symbolName) }
            }
            VaultManagementView(store: vaultStore)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }

    private var landscapeShell: some View {
        ZStack {
            animatedBackground
            HStack(spacing: 12) {
                landscapeSidebar
                    .frame(width: 230)
                Group {
                    if settingsSelected || vaultStore.vaults.isEmpty {
                        VaultManagementView(store: vaultStore)
                    } else if let vault = selectedVault {
                        vaultTab(for: vault)
                    } else {
                        VaultManagementView(store: vaultStore)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .padding(12)
        }
    }

    private var landscapeSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Oyloo")
                    .font(.title3.bold())
                Text("Capture vaults")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(vaultStore.vaults) { vault in
                        sidebarVaultButton(vault)
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            Button {
                settingsSelected = true
            } label: {
                sidebarLabel(
                    title: "Settings",
                    subtitle: "Vault setup",
                    symbolName: "gearshape",
                    tint: .secondary,
                    selected: settingsSelected || vaultStore.vaults.isEmpty
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func sidebarVaultButton(_ vault: Vault) -> some View {
        Button {
            selectedVaultKey = vault.key
            settingsSelected = false
        } label: {
            sidebarLabel(
                title: vault.displayName,
                subtitle: vault.key,
                symbolName: vault.symbolName,
                tint: vault.tintColor,
                selected: !settingsSelected && selectedVaultKey == vault.key
            )
        }
        .buttonStyle(.plain)
    }

    private func sidebarLabel(title: String, subtitle: String, symbolName: String, tint: Color, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.headline)
                .foregroundStyle(selected ? .white : tint)
                .frame(width: 34, height: 34)
                .background(selected ? tint : tint.opacity(0.15), in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(selected ? .white.opacity(0.78) : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? .white : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(selected ? tint.opacity(0.95) : Color.primary.opacity(0.04), in: .rect(cornerRadius: 14))
    }

    private var selectedVault: Vault? {
        guard let selectedVaultKey else { return nil }
        return vaultStore.vault(forKey: selectedVaultKey)
    }

    private func ensureSelection() {
        let keys = vaultStore.vaults.map(\.key)
        if keys.isEmpty {
            selectedVaultKey = nil
            settingsSelected = true
            return
        }
        if settingsSelected {
            return
        }
        if selectedVaultKey.map({ keys.contains($0) }) != true {
            selectedVaultKey = keys[0]
        }
    }

    @ViewBuilder
    private func vaultTab(for vault: Vault) -> some View {
        let groups = groupedEntries(for: vault.key)
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("No \(vault.displayName.lowercased()) shares yet", systemImage: vault.symbolName)
                    } description: {
                        Text("Share a URL, photo, file, or text from any app and pick \(vault.displayName) in the picker.")
                    } actions: {
                        feedStatus
                    }
                } else {
                    List {
                        if case .failed = feed.state {
                            Section { feedStatus }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        ForEach(groups, id: \.day) { group in
                            Section(group.header) {
                                ForEach(group.entries) { entry in
                                    entryRow(entry)
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
                    .refreshable {
                        reload()
                        await feed.refresh()
                    }
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
            .background { animatedBackground }
        }
    }

    /// One row of the list: either still in this device's outbox, or already
    /// on the server. Both carry a date, which is all the grouping needs.
    private enum FeedEntry: Identifiable {
        case local(SharedItem)
        case remote(ServerCapture)

        var id: String {
            switch self {
            case .local(let item): "local-\(item.id.uuidString)"
            case .remote(let capture): "remote-\(capture.id)"
            }
        }

        var date: Date {
            switch self {
            case .local(let item): item.sharedAt
            case .remote(let capture): capture.createdAt
            }
        }

        var localItem: SharedItem? {
            if case .local(let item) = self { return item }
            return nil
        }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let header: String
        let entries: [FeedEntry]
        var id: Date { day }
    }

    private func groupedEntries(for vaultKey: String) -> [DayGroup] {
        let calendar = Calendar.current
        let local = items
            .filter { $0.vaultKey == vaultKey }
            .map(FeedEntry.local)
        let remote = feed.captures(forVaultKey: vaultKey).map(FeedEntry.remote)
        let sorted = (local + remote).sorted(by: { $0.date > $1.date })
        let grouped = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            DayGroup(day: day, header: dayHeader(for: day), entries: grouped[day] ?? [])
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: FeedEntry) -> some View {
        switch entry {
        case .local(let item): ItemRow(item: item)
        case .remote(let capture): ServerCaptureRow(capture: capture)
        }
    }

    /// Why the server half of the list might be missing. Silent while it
    /// loads for the first time and once it has loaded.
    @ViewBuilder
    private var feedStatus: some View {
        switch feed.state {
        case .idle, .loading, .loaded:
            EmptyView()
        case .failed(let reason):
            VStack(spacing: 8) {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await feed.refresh() } }
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity)
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

    /// Swipe-to-delete removes from this device's outbox only; a capture the
    /// server already holds is not this screen's to destroy.
    private func delete(from group: DayGroup, offsets: IndexSet) {
        let removed = offsets.compactMap { group.entries[$0].localItem }
        guard !removed.isEmpty else { return }
        for item in removed { SharedStore.deleteAttachment(of: item) }
        let removedIDs = Set(removed.map { $0.id })
        items.removeAll { removedIDs.contains($0.id) }
        SharedStore.replaceAll(items)
    }

    private func reload() {
        items = SharedStore.readAll()
    }

    private var animatedBackground: some View {
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
                .frame(height: verticalSizeClass == .compact ? 150 : 260)
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
                HStack(spacing: 6) {
                    Text(item.sharedAt, style: .time)
                    // An item stays in the outbox after it ships, so the
                    // shipped list decides the label; the server's own copy
                    // appears as its own row.
                    if SharedStore.isShipped(item.id) {
                        Label("Sent", systemImage: "checkmark.circle")
                            .labelStyle(.titleAndIcon)
                    } else {
                        Label("Waiting to send", systemImage: "arrow.up.circle")
                            .labelStyle(.titleAndIcon)
                    }
                }
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

/// A capture the server already holds. Its file lives there, not here, so the
/// row shows what the server knows and offers no preview or delete.
private struct ServerCaptureRow: View {
    let capture: ServerCapture

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                if let title = capture.title, !title.isEmpty {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(capture.createdAt, style: .time)
                    Label("On the server", systemImage: "checkmark.icloud")
                        .labelStyle(.titleAndIcon)
                    if capture.podcast == true {
                        Label("Podcast", systemImage: "mic")
                            .labelStyle(.titleAndIcon)
                    }
                    if let transcript = transcriptLabel {
                        Text(transcript)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .contentShape(.rect(cornerRadius: 14))
    }

    private var icon: String {
        guard let mime = capture.mimeType else { return "doc" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("image/") { return "photo" }
        if mime.contains("pdf") { return "doc.richtext" }
        return "doc"
    }

    /// Only audio is transcribed, so the state is noise on anything else.
    private var transcriptLabel: String? {
        guard capture.isAudio, let state = capture.transcriptState else { return nil }
        switch state {
        case "done": return "Transcribed"
        case "pending": return "Transcribing…"
        case "failed": return "Transcript failed"
        default: return nil
        }
    }
}

#Preview {
    ContentView(vaultStore: VaultStore())
}
