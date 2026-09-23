import SwiftUI

/// Today first, then the sections the server allows, then Settings. A tab
/// bar on iPhone, a sidebar where the width allows.
struct RootView: View {
    @Bindable var vaultStore: VaultStore
    @State private var data = FamilyData()
    @State private var selection: AppSection = .today
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    List(data.sections, selection: selectionOptional) { section in
                        label(section).tag(section)
                    }
                    .navigationTitle(Text("Oyloo"))
                } detail: {
                    screen(selection)
                }
            } else {
                TabView(selection: $selection) {
                    ForEach(data.sections) { section in
                        screen(section).tabItem { label(section) }.tag(section)
                    }
                }
            }
        }
        .task { await data.refreshAll() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await data.refreshAll() } }
        }
        .onChange(of: data.sections) { _, sections in
            if !sections.contains(selection) { selection = .today }
        }
    }

    private var selectionOptional: Binding<AppSection?> {
        Binding(get: { selection }, set: { selection = $0 ?? .today })
    }

    @ViewBuilder
    private func screen(_ section: AppSection) -> some View {
        switch section {
        case .today: TodayView(data: data) { selection = $0 }
        case .money: MoneyView(data: data)
        case .tasks: TasksView(data: data)
        case .captures: ContentView(vaultStore: vaultStore, embedded: true)
        case .settings: VaultManagementView(store: vaultStore)
        }
    }

    private func label(_ section: AppSection) -> some View {
        switch section {
        case .today: Label("Today", systemImage: "sun.max")
        case .money: Label("Money", systemImage: "eurosign.circle")
        case .tasks: Label("Tasks", systemImage: "checklist")
        case .captures: Label("Captures", systemImage: "tray.full")
        case .settings: Label("Settings", systemImage: "gearshape")
        }
    }
}
