import SwiftUI

// MARK: - Anh

struct GamePhotosView: View {
    let gameId: String

    @EnvironmentObject private var auth: AuthStore
    @State private var photos: [ApiPhoto] = []
    @State private var error: String?
    @State private var picking = false
    @State private var busy = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        ScrollView {
            if let error {
                Text(error).foregroundStyle(.red).font(.footnote).padding()
            }
            if photos.isEmpty && !busy {
                Text("Chưa có ảnh nào.").font(.footnote).foregroundStyle(.secondary).padding()
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(photos) { photo in
                    thumb(photo)
                        .contextMenu {
                            Button("Xoá", role: .destructive) { Task { await remove(photo) } }
                        }
                }
            }
            .padding(8)
        }
        .navigationTitle("Ảnh")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { picking = true } label: { Label("Thêm ảnh", systemImage: "camera") }
                .disabled(busy)
        }
        .sheet(isPresented: $picking) {
            ImagePicker { image in
                picking = false
                if let image { Task { await upload(image) } }
            }
        }
        .overlay { if busy { ProgressView() } }
        .task { await load() }
    }

    @ViewBuilder
    private func thumb(_ photo: ApiPhoto) -> some View {
        if let data = Data(base64Encoded: photo.thumbData), let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 100)
                .clipped()
                .cornerRadius(8)
        } else {
            Color.gray.opacity(0.2).frame(height: 100).cornerRadius(8)
        }
    }

    private func load() async {
        error = await auth.perform { photos = try await $0.get("/api/games/\(gameId)/photos") }
    }

    private func upload(_ image: UIImage) async {
        // Ban thu nho gui kem: server khong tu tao, luoi anh doc thang field nay.
        guard let full = jpegBase64(image), let thumb = jpegBase64(image, maxEdge: 320) else {
            error = "Không đọc được ảnh."
            return
        }
        busy = true
        defer { busy = false }
        let body = PhotoInput(
            data: full,
            thumbData: thumb,
            width: Int(image.size.width),
            height: Int(image.size.height)
        )
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/games/\(gameId)/photos", body: body)
        }
        await load()
    }

    private func remove(_ photo: ApiPhoto) async {
        error = await auth.perform { try await $0.fire("/api/photos/\(photo.id)", method: "DELETE") }
        await load()
    }
}

// MARK: - Lich su

struct GameHistoryView: View {
    let gameId: String

    @EnvironmentObject private var auth: AuthStore
    @State private var events: [ApiGameEvent] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            if events.isEmpty { Text("Chưa có gì xảy ra.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(describeEvent(event.payload))
                        .font(.subheadline)
                        .strikethrough(event.undoneAt != nil)
                    Text(formatDateTime(event.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    // Chi khoan chi da xoa moi hoan tac duoc; server tu chan cac
                    // nhanh khac nen khong nhan ban o day.
                    if event.undoneAt == nil && event.payload.kind == "expense_removed" {
                        Button("Hoàn tác") { Task { await undo(event) } }
                    }
                }
            }
        }
        .navigationTitle("Lịch sử")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        error = await auth.perform {
            let body: Wrapped<[ApiGameEvent]> = try await $0.get("/api/games/\(gameId)/events")
            events = body.value ?? []
        }
    }

    private func undo(_ event: ApiGameEvent) async {
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/events/\(event.id)/undo")
        }
        await load()
    }
}

// MARK: - Tuy chon cuoc choi

struct GameOptionsView: View {
    let gameId: String

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var detail: ApiGameDetail?
    @State private var name = ""
    @State private var mode = "p2p"
    @State private var hostId = ""
    @State private var shareEmail = ""
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }

            if let detail {
                Section("Tên và cách chia") {
                    TextField("Tên cuộc chia", text: $name)
                    Picker("Cách chia", selection: $mode) {
                        ForEach(settlementModes, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    if mode == "pick" {
                        Picker("Gom về", selection: $hostId) {
                            Text("Chọn").tag("")
                            ForEach(detail.participants) { Text($0.name).tag($0.id) }
                        }
                    }
                    Button("Lưu") { Task { await saveSettings() } }
                }

                Section("Chia sẻ") {
                    if let link = detail.shareLink {
                        Toggle("Bật link xem", isOn: .constant(link.enabled))
                            .disabled(true)
                        Button {
                            UIPasteboard.general.string = "\(ApiClient.origin)/share/\(link.token)"
                        } label: {
                            Label("Copy link xem", systemImage: "doc.on.doc")
                        }
                        Button {
                            Task { await setLink(enabled: !link.enabled) }
                        } label: {
                            Label(link.enabled ? "Tắt link" : "Bật link",
                                  systemImage: link.enabled ? "link.badge.plus" : "link")
                        }
                    } else {
                        Button {
                            Task { await rotateLink() }
                        } label: {
                            Label("Tạo link xem", systemImage: "link")
                        }
                    }

                    ForEach(detail.collaborators) { person in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(person.name.isEmpty ? person.email : person.name)
                            if !person.name.isEmpty {
                                Text(person.email).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Bỏ", role: .destructive) { Task { await unshare(person) } }
                        }
                    }
                    HStack {
                        TextField("Email người cùng xem", text: $shareEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        Button("Mời") { Task { await share() } }
                            .disabled(shareEmail.isEmpty)
                    }
                }

                Section("Báo cáo") {
                    Button { copyReport(detail) } label: {
                        Label("Copy báo cáo", systemImage: "doc.on.clipboard")
                    }
                    Button { Task { await emailSummary() } } label: {
                        Label("Gửi email tổng kết", systemImage: "envelope")
                    }
                }

                Section {
                    Button {
                        Task { await toggleClosed(detail) }
                    } label: {
                        Label(detail.isClosed ? "Mở lại cuộc chia" : "Đóng cuộc chia",
                              systemImage: detail.isClosed ? "lock.open" : "lock")
                    }
                    Button { Task { await duplicate() } } label: {
                        Label("Nhân bản cuộc chia", systemImage: "plus.square.on.square")
                    }
                    if detail.isOwner {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Xoá cuộc chia", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Tùy chọn")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Xoá cuộc chia?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xoá", role: .destructive) { Task { await remove() } }
        } message: {
            Text("Cuộc chia vào thùng rác, phục hồi lại được.")
        }
        .overlay { if detail == nil && error == nil { ProgressView() } }
        .task { await load() }
    }

    private func load() async {
        error = await auth.perform { detail = try await $0.get("/api/games/\(gameId)") }
        if let detail {
            name = detail.name
            mode = detail.settlementMode
            hostId = detail.settlementHostId
        }
    }

    private func saveSettings() async {
        let body = GameUpdateInput(name: name, settlementMode: mode, settlementHostId: hostId)
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.patch("/api/games/\(gameId)", body: body)
        }
        await load()
    }

    private func rotateLink() async {
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/games/\(gameId)/share-links")
        }
        await load()
    }

    private func setLink(enabled: Bool) async {
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.patch(
                "/api/games/\(gameId)/share-link",
                body: EnabledInput(enabled: enabled)
            )
        }
        await load()
    }

    private func share() async {
        let email = shareEmail.trimmingCharacters(in: .whitespaces)
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post(
                "/api/games/\(gameId)/collaborators",
                body: EmailInput(email: email)
            )
        }
        if error == nil { shareEmail = "" }
        await load()
    }

    private func unshare(_ person: ApiCollaborator) async {
        // Chua tung dang nhap thi chi co email de goi ten.
        let path = person.userId.map { "/api/games/\(gameId)/collaborators/\($0)" }
            ?? "/api/games/\(gameId)/collaborators/pending/\(person.email.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? person.email)"
        error = await auth.perform { try await $0.fire(path, method: "DELETE") }
        await load()
    }

    private func emailSummary() async {
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/games/\(gameId)/email-summary")
        }
    }

    private func toggleClosed(_ detail: ApiGameDetail) async {
        let action = detail.isClosed ? "reopen" : "close"
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/games/\(gameId)/\(action)")
        }
        await load()
    }

    private func duplicate() async {
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/games/\(gameId)/duplicate")
        }
    }

    private func remove() async {
        error = await auth.perform { try await $0.fire("/api/games/\(gameId)", method: "DELETE") }
        if error == nil { dismiss() }
    }

    private func copyReport(_ detail: ApiGameDetail) {
        var lines = ["\(detail.name) — tổng \(formatVnd(detail.summary.totalExpense))", ""]
        for expense in detail.expenses {
            lines.append("• \(expense.title): \(formatVnd(expense.amount)) (\(detail.name(of: expense.payerParticipantId)) ứng)")
        }
        lines.append("")
        lines.append("Ai trả ai:")
        for row in detail.summary.settlements {
            lines.append("• \(detail.name(of: row.fromParticipantId)) → \(detail.name(of: row.toParticipantId)): \(formatVnd(row.amount))")
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
    }
}

// MARK: - Tat toan gop nhieu cuoc

struct CrossBalancesView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var data: ApiCrossGameBalances?
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            if let data {
                Section("Chuyển tiền") {
                    if data.settlements.isEmpty {
                        Text("Không ai phải chuyển tiền.").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(data.settlements) { TransferRow(from: $0.from, to: $0.to, amount: $0.amount) }
                }

                Section("Từng người") {
                    ForEach(data.people) { person in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(person.name)
                                Spacer()
                                Text(formatVnd(person.net))
                                    .monospacedDigit()
                                    .foregroundStyle(person.net < 0 ? .red : .green)
                            }
                            Text("\(person.games.count) cuộc · ứng \(formatVnd(person.paid))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !data.namesInOneGameOnly.isEmpty {
                    Section {
                        Text(data.namesInOneGameOnly.joined(separator: ", "))
                            .font(.footnote)
                    } header: {
                        Text("Chỉ thấy ở một cuộc")
                    } footer: {
                        Text("Có thể là gõ tên khác nhau nên chưa gộp được.")
                    }
                }
            }
        }
        .navigationTitle("Cần tất toán")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if data == nil && error == nil { ProgressView() } }
        .task { error = await auth.perform { data = try await $0.get("/api/cross-balances") } }
    }
}

// MARK: - So lien he

struct ContactsView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var contacts: [ApiContact] = []
    @State private var error: String?
    @State private var editing: ApiContact?
    @State private var adding = false

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            ForEach(contacts) { contact in
                Button { if contact.contactId != nil { editing = contact } } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name).foregroundStyle(.primary)
                        Text(contact.accountNo.isEmpty
                            ? "\(contact.gameCount) cuộc"
                            : "\(contact.bankId) · \(contact.accountNo)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    if contact.contactId != nil {
                        Button("Xoá", role: .destructive) { Task { await remove(contact) } }
                    }
                }
            }
            if contacts.isEmpty {
                Text("Sổ liên hệ trống.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Sổ liên hệ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { adding = true } label: { Label("Thêm", systemImage: "plus") }
        }
        .sheet(isPresented: $adding) { ContactFormView(contact: nil) { await load() } }
        .sheet(item: $editing) { contact in
            ContactFormView(contact: contact) { await load() }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        error = await auth.perform {
            let body: Wrapped<[ApiContact]> = try await $0.get("/api/contacts")
            contacts = body.value ?? []
        }
    }

    private func remove(_ contact: ApiContact) async {
        // Chi nguoi co dong trong bang contacts moi xoa duoc; nguoi suy ra tu
        // lich su khong co id nen swipe cung khong hien.
        guard let id = contact.contactId else { return }
        error = await auth.perform { try await $0.fire("/api/contacts/\(id)", method: "DELETE") }
        await load()
    }
}

private struct ContactFormView: View {
    let contact: ApiContact?
    let done: () async -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = PersonInput(name: "")
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tên", text: $input.name)
                TextField("Mã bank, vd VCB", text: $input.bankId)
                TextField("Số tài khoản", text: $input.accountNo).keyboardType(.numberPad)
                TextField("Tên chủ tài khoản", text: $input.accountName)
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(contact == nil ? "Thêm liên hệ" : "Sửa liên hệ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await save() } }
                        .disabled(input.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let contact {
                    input = PersonInput(
                        name: contact.name,
                        bankId: contact.bankId,
                        accountNo: contact.accountNo,
                        accountName: contact.accountName
                    )
                }
            }
        }
    }

    private func save() async {
        error = await auth.perform { client in
            if let id = contact?.contactId {
                let _: ApiClient.Ignored = try await client.patch("/api/contacts/\(id)", body: input)
            } else {
                let _: ApiClient.Ignored = try await client.post("/api/contacts", body: input)
            }
        }
        if error == nil {
            await done()
            dismiss()
        }
    }
}

// MARK: - Da dong / thung rac

struct GameArchiveView: View {
    enum Kind {
        case closed, trash

        var title: String { self == .closed ? "Cuộc đã đóng" : "Thùng rác" }
        var path: String { self == .closed ? "/api/games/closed" : "/api/games/trash" }
    }

    let kind: Kind

    @EnvironmentObject private var auth: AuthStore
    @State private var games: [ApiGame] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            ForEach(games) { game in
                if kind == .closed {
                    NavigationLink(value: Route.game(game.id)) { GameRow(game: game) }
                } else {
                    GameRow(game: game)
                        .swipeActions {
                            Button("Xoá hẳn", role: .destructive) { Task { await purge(game) } }
                            Button("Phục hồi") { Task { await restore(game) } }
                        }
                }
            }
            if games.isEmpty {
                Text(kind == .closed ? "Chưa đóng cuộc nào." : "Thùng rác trống.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        error = await auth.perform { games = try await $0.get(kind.path) }
    }

    private func restore(_ game: ApiGame) async {
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/games/\(game.id)/restore")
        }
        await load()
    }

    private func purge(_ game: ApiGame) async {
        error = await auth.perform { try await $0.fire("/api/games/\(game.id)/purge", method: "DELETE") }
        await load()
    }
}
