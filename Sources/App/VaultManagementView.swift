import SwiftUI

/// Settings UI for managing user-defined vaults.
/// - List existing vaults (with edit + swipe-delete)
/// - Tap + to add a new vault (sheet form)
/// - Tap a vault to edit it
struct VaultManagementView: View {
    @Bindable var store: VaultStore
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if store.vaults.isEmpty {
                    ContentUnavailableView {
                        Label("No vaults yet", systemImage: "tray")
                    } description: {
                        Text("Add a vault to start saving shares. Each vault has its own outbox and (later) its own sync target.")
                    } actions: {
                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Add your first vault", systemImage: "plus")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(store.vaults) { vault in
                            NavigationLink {
                                VaultEditView(store: store, existing: vault)
                            } label: {
                                vaultRow(vault)
                            }
                        }
                        .onDelete { offsets in
                            for idx in offsets {
                                store.remove(id: store.vaults[idx].id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Vaults")
            .toolbar {
                if !store.vaults.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                NavigationStack {
                    VaultEditView(store: store, existing: nil)
                }
            }
        }
    }

    private func vaultRow(_ vault: Vault) -> some View {
        HStack(spacing: 12) {
            Image(systemName: vault.symbolName)
                .font(.title2)
                .foregroundStyle(vault.tintColor)
                .frame(width: 36, height: 36)
                .background(vault.tintColor.opacity(0.15), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(vault.displayName)
                    .font(.body)
                Text(vault.key)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
        }
    }
}

/// Form to add or edit a single vault.
struct VaultEditView: View {
    @Bindable var store: VaultStore
    /// `nil` when adding a new vault, the existing instance when editing.
    let existing: Vault?

    @State private var displayName: String = ""
    @State private var key: String = ""
    @State private var symbolName: String = "folder.fill"
    @State private var tintColor: Color = .blue
    @State private var keyTouched = false

    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { existing != nil }
    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
            && !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Suggested SF Symbols — curated common picks. The text field
    /// accepts any SF Symbol name; this row is a quick chooser.
    private let suggestedSymbols = [
        "folder.fill", "heart.fill", "briefcase.fill", "leaf.fill",
        "book.fill", "bolt.fill", "flag.fill", "tag.fill",
        "person.fill", "globe", "house.fill", "graduationcap.fill",
        "tray.fill", "star.fill", "sparkles", "wand.and.stars"
    ]

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Display name (e.g. Work, Personal)", text: $displayName)
                    .onChange(of: displayName) { _, new in
                        if !keyTouched {
                            key = slugify(new)
                        }
                    }
                TextField("Key (lowercase slug)", text: $key)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .monospaced()
                    .onChange(of: key) { _, _ in keyTouched = true }
                if !key.isEmpty && key != slugify(key) {
                    Label("Slug should be lowercase letters, digits, and dashes only.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Appearance") {
                HStack(spacing: 16) {
                    Image(systemName: symbolName)
                        .font(.system(size: 36))
                        .foregroundStyle(tintColor)
                        .frame(width: 60, height: 60)
                        .background(tintColor.opacity(0.15), in: .rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayName.isEmpty ? "Preview" : displayName)
                            .font(.headline)
                        Text(symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospaced()
                    }
                    Spacer()
                }

                ColorPicker("Tint", selection: $tintColor, supportsOpacity: false)

                TextField("SF Symbol name", text: $symbolName)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .monospaced()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(suggestedSymbols, id: \.self) { sym in
                            Button {
                                symbolName = sym
                            } label: {
                                Image(systemName: sym)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        symbolName == sym
                                            ? tintColor.opacity(0.25)
                                            : Color(.secondarySystemBackground),
                                        in: .rect(cornerRadius: 8)
                                    )
                                    .foregroundStyle(symbolName == sym ? tintColor : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Vault" : "New Vault")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "Save" : "Add") {
                    let v = Vault(
                        id: existing?.id ?? UUID(),
                        key: slugify(key),
                        displayName: displayName.trimmingCharacters(in: .whitespaces),
                        symbolName: symbolName.trimmingCharacters(in: .whitespaces),
                        tintHex: tintColor.toHex() ?? "007AFF"
                    )
                    if isEditing {
                        store.update(v)
                    } else {
                        store.add(v)
                    }
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        .onAppear {
            if let v = existing {
                displayName = v.displayName
                key = v.key
                symbolName = v.symbolName
                tintColor = Color(hex: v.tintHex) ?? .blue
                keyTouched = true
            }
        }
    }

    /// Lowercase, ASCII-safe, dash-separated slug.
    private func slugify(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let filtered = lowered.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        var result = String(filtered)
        // Collapse multiple dashes + trim leading/trailing dashes
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result
    }
}
