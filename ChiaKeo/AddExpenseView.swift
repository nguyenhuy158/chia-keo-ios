import SwiftUI
import UIKit

struct AddExpenseView: View {
    let game: ApiGameDetail
    /// nil la them moi; co gia tri la sua khoan do.
    var expense: ApiExpense?
    let onSaved: () -> Void

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var amountText = ""
    @State private var payerId = ""
    @State private var splitIds: Set<String> = []
    @State private var error: String?
    @State private var busy = false
    @State private var scanning = false
    @State private var category = ""
    @State private var note = ""

    private var editing: Bool { expense != nil }

    /// Form nay chi chia deu; khoan dang chia tuy chinh se bi chia lai deu khi luu.
    private var willResetSplit: Bool { (expense?.splitMode ?? "equal") != "equal" }

    private var amount: Int? {
        // Nguoi ta go "125.000" hay "125 000" la binh thuong; loc lay chu so.
        let digits = amountText.filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        amount != nil && !payerId.isEmpty && !splitIds.isEmpty && !busy
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.footnote) }
                }

                if editing, willResetSplit {
                    Section {
                        Text("Khoản này đang chia tùy chỉnh. Lưu ở đây sẽ chia đều lại cho những người được chọn.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if !editing {
                Section {
                    Button {
                        scanning = true
                    } label: {
                        Label("Chụp hoá đơn", systemImage: "camera")
                    }
                    .disabled(busy)
                } footer: {
                    Text("Gemini đọc hoá đơn rồi điền sẵn tên, số tiền và người trả.")
                }
                }

                Section("Khoản chi") {
                    Picker("Danh mục", selection: $category) {
                        Text("Chưa phân loại").tag("")
                        ForEach(expenseCategories, id: \.id) { item in
                            Text("\(item.emoji) \(item.label)").tag(item.id)
                        }
                    }
                    TextField("Tên khoản chi", text: $title)
                    TextField("Số tiền", text: $amountText)
                        .keyboardType(.numberPad)
                    if let amount {
                        Text(formatVnd(amount)).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Ghi chú", text: $note)
                }

                Section("Ai trả") {
                    Picker("Người trả", selection: $payerId) {
                        ForEach(game.participants) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Chia cho") {
                    ForEach(game.participants) { participant in
                        Button {
                            toggle(participant.id)
                        } label: {
                            HStack {
                                Text(participant.name).foregroundStyle(.primary)
                                Spacer()
                                if splitIds.contains(participant.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(editing ? "Sửa khoản chi" : "Thêm khoản chi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await save() } }.disabled(!canSave)
                }
            }
            .overlay {
                if busy { ProgressView().padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            }
            .sheet(isPresented: $scanning) {
                ImagePicker { image in
                    scanning = false
                    if let image { Task { await scan(image) } }
                }
                .ignoresSafeArea()
            }
            .onAppear {
                if let expense {
                    if title.isEmpty { title = expense.title }
                    if amountText.isEmpty { amountText = String(expense.amount) }
                    if note.isEmpty { note = expense.note }
                    if category.isEmpty { category = expense.category }
                    if splitIds.isEmpty { splitIds = Set(expense.splitParticipantIds) }
                    if payerId.isEmpty { payerId = expense.payerParticipantId }
                }
                // Mac dinh chia deu cho ca nhom: gan nhu luon la y muon, va bo
                // chon nhanh hon la tich tay tung nguoi.
                if splitIds.isEmpty { splitIds = Set(game.participants.map(\.id)) }
                if payerId.isEmpty { payerId = game.participants.first?.id ?? "" }
            }
        }
    }

    private func toggle(_ id: String) {
        if splitIds.contains(id) { splitIds.remove(id) } else { splitIds.insert(id) }
    }

    private func scan(_ image: UIImage) async {
        guard let client = auth.client, let jpeg = jpegBase64(image) else {
            error = "Không đọc được ảnh"
            return
        }
        busy = true
        defer { busy = false }
        do {
            let response: AiSuggestionResponse = try await client.post(
                "/api/ai/receipt",
                body: ReceiptInput(gameId: game.id, image: .init(data: jpeg))
            )
            let suggestion = response.suggestion
            // Chi dien vao, khong tu luu: AI doc sai so tien la mat tien that.
            if !suggestion.title.isEmpty { title = suggestion.title }
            if suggestion.amount > 0 { amountText = String(suggestion.amount) }
            if !suggestion.payerParticipantId.isEmpty { payerId = suggestion.payerParticipantId }
            if !suggestion.splitParticipantIds.isEmpty { splitIds = Set(suggestion.splitParticipantIds) }
            error = nil
        } catch ApiError.unauthorized {
            auth.signOut(notice: "Phiên đã hết hạn, đăng nhập lại nhé.")
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        guard let client = auth.client, let amount else { return }
        busy = true
        defer { busy = false }
        // Giu nguyen kind: sua mot khoan "income" khong duoc bien no thanh "expense".
        let body = ExpenseInput(
            kind: expense?.kind ?? "expense",
            category: category,
            title: title,
            amount: amount,
            note: note,
            payerParticipantId: payerId,
            splitParticipantIds: Array(splitIds)
        )
        do {
            let _: ApiClient.Ignored = expense == nil
                ? try await client.post("/api/games/\(game.id)/expenses", body: body)
                : try await client.patch("/api/expenses/\(expense!.id)", body: body)
            onSaved()
            dismiss()
        } catch ApiError.unauthorized {
            auth.signOut(notice: "Phiên đã hết hạn, đăng nhập lại nhé.")
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Anh iPhone 12MP base64 la ~8MB, vuot tran AI_IMAGE_DATA_MAX_LENGTH cua worker.
/// Ha canh dai ve 1600px roi nen JPEG truoc khi gui.
func jpegBase64(_ image: UIImage, maxEdge: CGFloat = 1600) -> String? {
    let scale = min(1, maxEdge / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

    let renderer = UIGraphicsImageRenderer(size: size)
    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    return resized.jpegData(compressionQuality: 0.7)?.base64EncodedString()
}

/// UIImagePickerController chu khong PhotosPicker: cai nay mo duoc camera, va
/// chup hoa don la ly do app nay ton tai tren dien thoai.
struct ImagePicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        // May khong co camera (simulator) thi roi ve thu vien anh.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void

        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onPick(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(nil)
        }
    }
}
