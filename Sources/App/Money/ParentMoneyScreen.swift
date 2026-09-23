import Charts
import SwiftUI

struct ParentMoneyScreen: View {
    let kids: [KidMoney]
    let unassigned: [UnassignedAccount]
    let data: FamilyData

    @State private var addingKid = false

    var body: some View {
        List {
            Section("Children") {
                ForEach(kids) { kid in
                    NavigationLink {
                        KidMoneyScreen(kid: kid, editable: false, data: data)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(kid.displayName).font(.headline)
                                Spacer()
                                Text(euros(kid.balanceCents)).monospacedDigit()
                            }
                            HStack {
                                Text("Free \(euros(kid.freeCents))")
                                Spacer()
                                if let month = kid.month { Text("Spent \(euros(month.spentCents))") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if kids.contains(where: { !$0.monthly.isEmpty }) {
                Section("Spending by month") {
                    Chart(spendSeries(kids, months: 6), id: \.self) { point in
                        BarMark(x: .value("Month", point.month), y: .value("€", Double(point.cents) / 100))
                            .foregroundStyle(by: .value("Child", point.kid))
                            .position(by: .value("Child", point.kid))
                    }
                    .frame(height: 200)
                }
            }
            Section("Admin") {
                ForEach(kids) { kid in
                    NavigationLink {
                        KidAccountsView(kid: kid, unassigned: unassigned, data: data)
                    } label: {
                        Label("\(kid.displayName): accounts", systemImage: "building.columns")
                    }
                }
                Button { addingKid = true } label: { Label("Add child", systemImage: "person.badge.plus") }
            }
            FreshnessLabel(fetchedAt: data.money.fetchedAt, error: data.money.error)
        }
        .refreshable { await data.money.refresh() }
        .sheet(isPresented: $addingKid) { AddKidSheet(unassigned: unassigned, data: data) }
    }
}

/// Linked accounts are shown by a short form of their bank hash: the server
/// sends names only for accounts nobody owns yet.
struct KidAccountsView: View {
    let kid: KidMoney
    let unassigned: [UnassignedAccount]
    let data: FamilyData
    @State private var failure: String?

    var body: some View {
        List {
            if let failure { Text(failure).foregroundStyle(.red).font(.footnote) }
            Section("Linked") {
                if kid.hashes.isEmpty { Text("No accounts linked").foregroundStyle(.secondary) }
                ForEach(kid.hashes, id: \.self) { hash in
                    Text("…" + hash.suffix(8)).monospaced()
                }
                .onDelete { offsets in
                    let hashes = offsets.map { kid.hashes[$0] }
                    Task {
                        for hash in hashes {
                            await act { try await AppAPI.unlinkAccount(userId: kid.userId, hash: hash) }
                        }
                    }
                }
            }
            Section("Not linked to anyone") {
                if unassigned.isEmpty { Text("None").foregroundStyle(.secondary) }
                ForEach(unassigned) { account in
                    Button {
                        Task { await act { try await AppAPI.linkAccounts(userId: kid.userId, hashes: [account.identificationHash]) } }
                    } label: {
                        accountLabel(account)
                    }
                }
            }
        }
        .navigationTitle(kid.displayName)
    }

    private func act(_ action: @escaping () async throws -> Void) async {
        do {
            try await action()
            failure = nil
            await data.money.refresh()
        } catch {
            failure = moneyFailureText(error)
        }
    }
}

func accountLabel(_ account: UnassignedAccount) -> some View {
    VStack(alignment: .leading) {
        Text(account.name ?? account.product ?? "…" + account.identificationHash.suffix(8))
        Text("\(account.currency ?? "?") · \(account.txCount) ops · \(account.lastActivity ?? "—")")
            .font(.caption2).foregroundStyle(.secondary)
    }
}

struct AddKidSheet: View {
    let unassigned: [UnassignedAccount]
    let data: FamilyData
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var picked: Set<String> = []
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("E-mail", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password, at least 8 characters", text: $password)
                        .textContentType(.newPassword)
                }
                if !unassigned.isEmpty {
                    Section("Bank accounts") {
                        ForEach(unassigned) { account in
                            Button {
                                if picked.contains(account.id) { picked.remove(account.id) } else { picked.insert(account.id) }
                            } label: {
                                HStack {
                                    accountLabel(account)
                                    Spacer()
                                    if picked.contains(account.id) { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .navigationTitle(Text("Add child"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                }
            }
        }
    }

    private func create() async {
        do {
            try await AppAPI.addKid(email: email, password: password, displayName: name,
                                    accountHashes: Array(picked))
            await data.money.refresh()
            dismiss()
        } catch {
            failure = moneyFailureText(error)
        }
    }
}
