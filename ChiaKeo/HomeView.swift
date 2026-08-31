import SwiftUI

/// Bon tab, khop dieu huong ben web (src/routes/AppLayout.tsx).
struct RootTabs: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Cuộc chia", systemImage: "list.bullet.rectangle") }
            ShuttlesView()
                .tabItem { Label("Kho cầu", systemImage: "shippingbox") }
            FunStatsView()
                .tabItem { Label("Thống kê", systemImage: "chart.bar") }
            SettingsView()
                .tabItem { Label("Cài đặt", systemImage: "gearshape") }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var games: [ApiGame] = []
    @State private var cross: ApiCrossGameBalances?
    @State private var error: String?
    @State private var loading = true
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }

                Section("Đang chơi") {
                    ForEach(games) { game in
                        NavigationLink(value: Route.game(game.id)) { GameRow(game: game) }
                    }
                    if games.isEmpty && !loading {
                        Text("Không có cuộc nào đang chơi. Bấm + để bắt đầu.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let cross, !cross.settlements.isEmpty {
                    Section {
                        ForEach(cross.settlements.prefix(5)) { row in
                            TransferRow(from: row.from, to: row.to, amount: row.amount)
                        }
                        NavigationLink(value: Route.crossBalances) {
                            Label("Xem tất toán chi tiết", systemImage: "arrow.left.arrow.right")
                        }
                            .font(.footnote)
                    } header: {
                        Text("Cần tất toán")
                    } footer: {
                        Text("Gộp tất cả cuộc đang chơi, đối chiếu người theo tên.")
                    }
                }

                Section {
                    NavigationLink(value: Route.contacts) {
                        Label("Sổ liên hệ", systemImage: "person.text.rectangle")
                    }
                    NavigationLink(value: Route.closedGames) {
                        Label("Cuộc đã đóng", systemImage: "lock")
                    }
                    NavigationLink(value: Route.trash) {
                        Label("Thùng rác", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Cuộc chia")
            .navigationDestination(for: Route.self) { $0.view }
            .toolbar {
                Button { creating = true } label: { Label("Cuộc mới", systemImage: "plus") }
            }
            .sheet(isPresented: $creating) {
                NewGameView { await load() }
            }
            .overlay { if loading && games.isEmpty { ProgressView() } }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        error = await auth.perform {
            games = try await $0.get("/api/games")
            // Tat toan gop chi co nghia khi con it nhat hai cuoc.
            cross = games.count > 1 ? try await $0.get("/api/cross-balances") : nil
        }
    }
}

/// Mot cho khai bao moi diem den, de NavigationStack nao cung dieu huong duoc.
enum Route: Hashable {
    case game(String)
    case crossBalances
    case contacts
    case closedGames
    case trash
    case gamePhotos(String)
    case gameHistory(String)
    case gameOptions(String)
    case mcpTokens

    @ViewBuilder
    var view: some View {
        switch self {
        case .game(let id): GameDetailView(gameId: id)
        case .crossBalances: CrossBalancesView()
        case .contacts: ContactsView()
        case .closedGames: GameArchiveView(kind: .closed)
        case .trash: GameArchiveView(kind: .trash)
        case .gamePhotos(let id): GamePhotosView(gameId: id)
        case .gameHistory(let id): GameHistoryView(gameId: id)
        case .gameOptions(let id): GameOptionsView(gameId: id)
        case .mcpTokens: McpTokensView()
        }
    }
}

struct GameRow: View {
    let game: ApiGame

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(game.name).fontWeight(.medium)
            Text("\(game.participantCount) người · \(game.expenseCount) khoản · \(formatShortDate(game.createdAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct TransferRow: View {
    let from: String
    let to: String
    let amount: Int

    var body: some View {
        HStack {
            Text(from)
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
            Text(to)
            Spacer()
            Text(formatVnd(amount)).monospacedDigit()
        }
        .font(.subheadline)
    }
}

private struct NewGameView: View {
    let done: () async -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = GameInput(name: "")
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tên cuộc chia", text: $input.name)
                    Stepper("Tạo sẵn \(input.participantCount) người", value: $input.participantCount, in: 0...20)
                }
                Section("Chuyển tiền") {
                    Picker("Cách chia", selection: $input.settlementMode) {
                        ForEach(settlementModes, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Cuộc mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tạo") { Task { await save() } }
                        .disabled(input.name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/games", body: input)
        }
        if error == nil {
            await done()
            dismiss()
        }
    }
}
