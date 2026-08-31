import SwiftUI

/// Bon muc duoi day khop src/components/MobileGameNav.tsx ben web.
private enum GameSection: String, CaseIterable {
    case people, expenses, summary

    var label: String {
        switch self {
        case .people: "Người"
        case .expenses: "Chi"
        case .summary: "Tổng kết"
        }
    }
}

struct GameDetailView: View {
    let gameId: String

    @EnvironmentObject private var auth: AuthStore
    @State private var detail: ApiGameDetail?
    @State private var error: String?
    @State private var section = GameSection.expenses
    @State private var adding = false
    @State private var addingPerson = false
    @State private var transferring = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mục", selection: $section) {
                ForEach(GameSection.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            List {
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
                if let detail {
                    switch section {
                    case .people: PeopleSection(detail: detail, reload: load)
                    case .expenses: ExpensesSection(detail: detail, reload: load)
                    case .summary: SummarySection(detail: detail)
                    }
                }
            }
        }
        .navigationTitle(detail?.name ?? "Đang tải")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let detail, !detail.isClosed {
                        Button("Thêm khoản chi", systemImage: "plus") { adding = true }
                        Button("Thêm người", systemImage: "person.badge.plus") { addingPerson = true }
                        Button("Ghi chuyển tiền", systemImage: "arrow.left.arrow.right") { transferring = true }
                    }
                    NavigationLink(value: Route.gamePhotos(gameId)) {
                        Label("Ảnh", systemImage: "photo.on.rectangle")
                    }
                    NavigationLink(value: Route.gameHistory(gameId)) {
                        Label("Lịch sử", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink(value: Route.gameOptions(gameId)) {
                        Label("Tùy chọn cuộc chơi", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Label("Thêm", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $adding) {
            if let detail { AddExpenseView(game: detail) { Task { await load() } } }
        }
        .sheet(isPresented: $addingPerson) {
            if let detail { PersonFormView(gameId: detail.id) { await load() } }
        }
        .sheet(isPresented: $transferring) {
            if let detail { TransferFormView(detail: detail) { await load() } }
        }
        .overlay { if detail == nil && error == nil { ProgressView() } }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        error = await auth.perform { detail = try await $0.get("/api/games/\(gameId)") }
    }
}

// MARK: - Nguoi

private struct PeopleSection: View {
    let detail: ApiGameDetail
    let reload: () async -> Void

    @EnvironmentObject private var auth: AuthStore
    @State private var editing: ApiParticipant?
    @State private var picking = false
    @State private var error: String?

    var body: some View {
        Section {
            if !detail.isClosed {
                Button {
                    picking = true
                } label: {
                    Label("Thêm từ sổ liên hệ", systemImage: "person.crop.circle.badge.plus")
                        .font(.footnote)
                }
            }
            ForEach(detail.participants) { person in
                Button { editing = person } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name).foregroundStyle(.primary)
                        if !person.accountNo.isEmpty {
                            Text("\(person.bankId) · \(person.accountNo)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Xoá", role: .destructive) { Task { await remove(person) } }
                }
            }
        } footer: {
            if let error { Text(error).foregroundStyle(.red) }
        }
        .sheet(item: $editing) { person in
            PersonFormView(gameId: detail.id, participant: person) { await reload() }
        }
        .sheet(isPresented: $picking) {
            ContactPickerView(gameId: detail.id, participants: detail.participants) { await reload() }
        }
    }

    private func remove(_ person: ApiParticipant) async {
        error = await auth.perform { try await $0.fire("/api/participants/\(person.id)", method: "DELETE") }
        await reload()
    }
}

struct PersonFormView: View {
    let gameId: String
    var participant: ApiParticipant?
    let done: () async -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = PersonInput(name: "")
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Tên", text: $input.name)
                Section("Tài khoản nhận tiền (không bắt buộc)") {
                    TextField("Mã bank, vd VCB", text: $input.bankId)
                    TextField("Số tài khoản", text: $input.accountNo)
                        .keyboardType(.numberPad)
                    TextField("Tên chủ tài khoản", text: $input.accountName)
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle(participant == nil ? "Thêm người" : "Sửa người")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await save() } }
                        .disabled(input.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let participant {
                    input = PersonInput(
                        name: participant.name,
                        bankId: participant.bankId,
                        accountNo: participant.accountNo,
                        accountName: participant.accountName
                    )
                }
            }
        }
    }

    private func save() async {
        error = await auth.perform { client in
            if let participant {
                let _: ApiClient.Ignored = try await client.patch("/api/participants/\(participant.id)", body: input)
            } else {
                let _: ApiClient.Ignored = try await client.post("/api/games/\(gameId)/participants", body: input)
            }
        }
        if error == nil {
            await done()
            dismiss()
        }
    }
}

// MARK: - Chon tu so lien he

/**
 * Chon nhieu nguoi quen mot luot roi them bang /participants/batch, khop
 * ContactPicker.tsx ben web. Nguoi da co trong cuoc chia bi mo di va khong chon
 * duoc — doi chieu theo TEN da chuan hoa, y nhu server (normalizeContactName).
 */
struct ContactPickerView: View {
    let gameId: String
    let participants: [ApiParticipant]
    let done: () async -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [ApiContact] = []
    @State private var chosen: Set<String> = []
    @State private var loading = true
    @State private var error: String?

    /// "hồng " va "Hồng" la cung mot nguoi (shared/contacts.ts).
    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    private var alreadyIn: Set<String> {
        Set(participants.map { Self.normalize($0.name) })
    }

    /// Nguoi da co xuong cuoi: cho trong tam danh cho nguoi con chon duoc.
    private var sorted: [ApiContact] {
        let alreadyIn = alreadyIn
        return contacts.sorted { alreadyIn.contains($0.key) == alreadyIn.contains($1.key)
            ? false
            : !alreadyIn.contains($0.key) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                if contacts.isEmpty && !loading {
                    Text("Sổ liên hệ còn trống. Thêm người vài cuộc chia rồi họ tự vào đây.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(sorted) { contact in
                    let inGame = alreadyIn.contains(contact.key)
                    Button {
                        if chosen.contains(contact.key) {
                            chosen.remove(contact.key)
                        } else {
                            chosen.insert(contact.key)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                Text(contact.accountNo.isEmpty
                                     ? "\(contact.gameCount) cuộc · chưa có QR"
                                     : "\(contact.gameCount) cuộc · \(contact.bankId) \(contact.accountNo)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if inGame {
                                Text("đã có").font(.caption).foregroundStyle(.secondary)
                            } else if chosen.contains(contact.key) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            } else {
                                Image(systemName: "plus.circle").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(inGame ? .secondary : .primary)
                    .disabled(inGame)
                }
            }
            .overlay { if loading { ProgressView() } }
            .navigationTitle("Người quen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Thêm \(picked.count) người") { Task { await add() } }
                        .disabled(picked.isEmpty)
                }
            }
            .task { await load() }
        }
    }

    /// Nguoi da chon va van con chon duoc (loc lai cho chac).
    private var picked: [ApiContact] {
        let alreadyIn = alreadyIn
        return contacts.filter { chosen.contains($0.key) && !alreadyIn.contains($0.key) }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        error = await auth.perform {
            let wrapped: Wrapped<[ApiContact]> = try await $0.get("/api/contacts")
            contacts = wrapped.value ?? []
        }
    }

    private func add() async {
        let people = picked.map {
            PersonInput(name: $0.name, bankId: $0.bankId,
                        accountNo: $0.accountNo, accountName: $0.accountName)
        }
        guard !people.isEmpty else { return }
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post(
                "/api/games/\(gameId)/participants/batch", body: PeopleInput(people: people))
        }
        if error == nil {
            await done()
            dismiss()
        }
    }
}

// MARK: - Chi

private struct ExpensesSection: View {
    let detail: ApiGameDetail
    let reload: () async -> Void

    @EnvironmentObject private var auth: AuthStore
    @State private var error: String?

    var body: some View {
        Section {
            if detail.expenses.isEmpty {
                Text("Chưa có khoản chi nào.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(detail.expenses) { expense in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(categoryEmoji(expense.category))
                        Text(expense.title).fontWeight(.medium)
                        Spacer()
                        // "income" la khoan dao nguoc, hien dau tru cho khoi nham
                        // voi mot khoan chi cung so tien.
                        Text(formatVnd(expense.kind == "income" ? -expense.amount : expense.amount))
                            .monospacedDigit()
                    }
                    Text("\(detail.name(of: expense.payerParticipantId)) trả · \(expense.splitParticipantIds.count) người chia")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    if !detail.isClosed {
                        Button("Xoá", role: .destructive) { Task { await remove(expense) } }
                    }
                }
            }
        } header: {
            Text("Tổng chi \(formatVnd(detail.summary.totalExpense))")
        } footer: {
            if let error { Text(error).foregroundStyle(.red) }
        }
    }

    private func remove(_ expense: ApiExpense) async {
        error = await auth.perform { try await $0.fire("/api/expenses/\(expense.id)", method: "DELETE") }
        await reload()
    }
}

// MARK: - Tong ket

private struct SummarySection: View {
    let detail: ApiGameDetail

    var body: some View {
        Section("Ai trả ai") {
            if detail.summary.settlements.isEmpty {
                Text("Không ai phải chuyển tiền.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(detail.summary.settlements) { row in
                TransferRow(
                    from: detail.name(of: row.fromParticipantId),
                    to: detail.name(of: row.toParticipantId),
                    amount: row.amount
                )
            }
        }

        Section("Từng người") {
            ForEach(detail.summary.balances, id: \.participantId) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(detail.name(of: row.participantId))
                        Spacer()
                        Text(formatVnd(row.balance))
                            .monospacedDigit()
                            .foregroundStyle(row.balance < 0 ? .red : .green)
                    }
                    Text("Ứng \(formatVnd(row.paid)) · phần \(formatVnd(row.owed))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section("Cuộc chia") {
            LabeledContent("Mã", value: detail.code)
            LabeledContent("Cách chia", value: settlementLabel(detail.settlementMode))
            LabeledContent("Trạng thái", value: detail.isClosed ? "Đã đóng" : "Đang chơi")
        }
    }
}

// MARK: - Ghi chuyen tien

private struct TransferFormView: View {
    let detail: ApiGameDetail
    let done: () async -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var from = ""
    @State private var to = ""
    @State private var amount = ""
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Người trả", selection: $from) {
                    Text("Chọn").tag("")
                    ForEach(detail.participants) { Text($0.name).tag($0.id) }
                }
                Picker("Người nhận", selection: $to) {
                    Text("Chọn").tag("")
                    ForEach(detail.participants) { Text($0.name).tag($0.id) }
                }
                TextField("Số tiền", text: $amount).keyboardType(.numberPad)
                TextField("Ghi chú", text: $note)
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Ghi chuyển tiền")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await save() } }.disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !from.isEmpty && !to.isEmpty && from != to && (Int(amount) ?? 0) > 0
    }

    private func save() async {
        let body = TransferInput(
            fromParticipantId: from,
            toParticipantId: to,
            amount: Int(amount) ?? 0,
            note: note
        )
        error = await auth.perform {
            let _: ApiClient.Ignored = try await $0.post("/api/games/\(detail.id)/transfers", body: body)
        }
        if error == nil {
            await done()
            dismiss()
        }
    }
}
