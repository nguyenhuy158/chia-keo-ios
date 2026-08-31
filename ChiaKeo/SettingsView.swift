import SwiftUI

// MARK: - Kho cau

struct ShuttlesView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var stock: ApiShuttleStock?
    @State private var error: String?
    @State private var quantity = "1"
    @State private var note = ""

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }

                Section {
                    HStack {
                        Text("Còn lại").font(.subheadline)
                        Spacer()
                        Text("\(stock?.stock ?? 0) cầu")
                            .font(.title2.bold())
                            .monospacedDigit()
                    }
                }

                Section("Ghi thao tác") {
                    TextField("Số lượng", text: $quantity).keyboardType(.numberPad)
                    TextField("Ghi chú", text: $note)
                    HStack {
                        Button("Mua thêm") { Task { await record("add") } }
                        Spacer()
                        Button("Đánh hết") { Task { await record("use") } }
                        Spacer()
                        Button("Đặt lại") { Task { await record("set") } }
                    }
                    .buttonStyle(.bordered)
                    .font(.footnote)
                }

                Section("Gần đây") {
                    ForEach(stock?.entries ?? []) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entryLabel(entry.kind))
                                Spacer()
                                Text(entry.delta > 0 ? "+\(entry.delta)" : "\(entry.delta)")
                                    .monospacedDigit()
                                    .foregroundStyle(entry.delta < 0 ? .red : .green)
                                Text("→ \(entry.stockAfter)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.note.isEmpty
                                ? formatDateTime(entry.createdAt)
                                : "\(entry.note) · \(formatDateTime(entry.createdAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Xoá", role: .destructive) { Task { await remove(entry) } }
                        }
                    }
                    if stock?.entries.isEmpty ?? true {
                        Text("Chưa ghi gì.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Kho cầu")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func entryLabel(_ kind: String) -> String {
        switch kind {
        case "add": "Mua thêm"
        case "use": "Đánh hết"
        default: "Đặt lại kho"
        }
    }

    private func load() async {
        error = await auth.perform { stock = try await $0.get("/api/shuttles") }
    }

    private func record(_ kind: String) async {
        let body = ShuttleEntryInput(kind: kind, quantity: Int(quantity) ?? 0, note: note)
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/shuttles/entries", body: body)
        }
        if error == nil { note = "" }
        await load()
    }

    private func remove(_ entry: ApiShuttleEntry) async {
        error = await auth.perform {
            try await $0.fire("/api/shuttles/entries/\(entry.id)", method: "DELETE")
        }
        await load()
    }
}

// MARK: - Thong ke vui

struct FunStatsView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var stats: ApiFunStats?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                if let stats {
                    Section {
                        LabeledContent("Số cuộc chia", value: "\(stats.gameCount)")
                        LabeledContent("Tổng đã chi", value: formatVnd(stats.totalExpense))
                        if let day = stats.favoriteWeekday {
                            LabeledContent("Hay chơi nhất", value: weekdayName(day))
                        }
                    }

                    Section("Vài con số") {
                        if let payer = stats.topPayer {
                            badge("Ứng nhiều nhất", payer.name, formatVnd(payer.totalPaid))
                        }
                        if let active = stats.mostActive {
                            badge("Đi nhiều nhất", active.name, "\(active.gameCount) cuộc")
                        }
                        if let expense = stats.biggestExpense {
                            badge("Khoản to nhất", expense.title, formatVnd(expense.amount))
                        }
                        if let game = stats.biggestGame {
                            badge("Cuộc đông nhất", game.name, "\(game.participantCount) người")
                        }
                    }

                    if stats.omittedGameCount > 0 {
                        Section {
                            Text("Bỏ bớt \(stats.omittedGameCount) cuộc để không quá tải.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Thống kê vui")
            .overlay { if stats == nil && error == nil { ProgressView() } }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func badge(_ title: String, _ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(name)
                Spacer()
                Text(detail).monospacedDigit()
            }
        }
    }

    private func load() async {
        error = await auth.perform { stats = try await $0.get("/api/fun-stats") }
    }
}

// MARK: - Cai dat

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var name = ""
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }

                Section("Tên hiển thị") {
                    TextField("Tên", text: $name)
                    Button(saved ? "Đã lưu" : "Lưu") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section {
                    NavigationLink(value: Route.mcpTokens) {
                        Label("Token MCP", systemImage: "key.horizontal")
                    }
                }

                Section {
                    Button(role: .destructive) { auth.signOut() } label: {
                        Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Cài đặt")
            .navigationDestination(for: Route.self) { $0.view }
            .task { await load() }
        }
    }

    private func load() async {
        error = await auth.perform {
            let session: ApiSession = try await $0.get("/api/session")
            name = session.user?.name ?? ""
        }
    }

    private func save() async {
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.patch("/api/profile", body: ProfileInput(name: name))
        }
        saved = error == nil
    }
}

// MARK: - Token MCP

struct McpTokensView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var tokens: [ApiMcpToken] = []
    @State private var error: String?
    @State private var newName = ""
    @State private var secret: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }

            if let secret {
                Section {
                    Text(secret).font(.footnote.monospaced()).textSelection(.enabled)
                    Button("Copy") { UIPasteboard.general.string = secret }
                } header: {
                    Text("Token mới")
                } footer: {
                    Text("Chỉ hiện đúng lần này. Copy đi rồi mới rời màn hình.")
                }
            }

            Section("Tạo token") {
                TextField("Tên, vd Claude Code ở máy bàn", text: $newName)
                Button("Tạo") { Task { await create() } }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Đang có") {
                ForEach(tokens) { token in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(token.name)
                        Text("\(token.tokenPrefix)… · \(token.active ? "còn dùng" : "đã thu hồi")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Thu hồi", role: .destructive) { Task { await revoke(token) } }
                    }
                }
                if tokens.isEmpty {
                    Text("Chưa có token nào.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Token MCP")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        error = await auth.perform { tokens = try await $0.get("/api/mcp-tokens") }
    }

    private func create() async {
        // App chi tao token du quyen doc; muon quyen le hon thi lam ben web.
        let body = McpTokenInput(name: newName, scopes: mcpScopeLabels.map(\.id), expiresInDays: nil)
        error = await auth.perform {
            let created: ApiCreatedMcpToken = try await $0.post("/api/mcp-tokens", body: body)
            secret = created.secret
        }
        if error == nil { newName = "" }
        await load()
    }

    private func revoke(_ token: ApiMcpToken) async {
        error = await auth.perform { try await $0.fire("/api/mcp-tokens/\(token.id)", method: "DELETE") }
        await load()
    }
}
