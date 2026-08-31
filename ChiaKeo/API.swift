import Foundation

// Cac struct duoi day la ban chieu cua shared/api-types.ts ben chia-keo. Chi
// khai bao field app THAT SU dung — Codable bo qua field la, nen server them
// field moi khong lam app vo.

struct ApiGame: Decodable, Identifiable {
    let id: String
    let code: String
    let name: String
    let createdAt: String
    let participantCount: Int
    let expenseCount: Int
    let closedAt: String?
    let closeMode: String
    let isOwner: Bool
}

struct ApiParticipant: Decodable, Identifiable {
    let id: String
    let name: String
    let bankId: String
    let accountNo: String
    let accountName: String
}

struct ApiExpenseSplit: Decodable {
    let participantId: String
    let amount: Int
}

struct ApiExpense: Decodable, Identifiable {
    let id: String
    let kind: String
    let category: String
    let title: String
    let amount: Int
    let note: String
    let payerParticipantId: String
    let splitMode: String
    let splitParticipantIds: [String]
    /// Phan chia thuc te cua tung nguoi. Optional vi payload cu (va vai test)
    /// khong co field nay — Swift bo qua gia tri mac dinh khi decode.
    let splits: [ApiExpenseSplit]?
    let createdAt: String
}

struct BalanceRow: Decodable {
    let participantId: String
    let paid: Int
    let owed: Int
    let balance: Int
}

struct SettlementRow: Decodable, Identifiable {
    let fromParticipantId: String
    let toParticipantId: String
    let amount: Int

    var id: String { "\(fromParticipantId)-\(toParticipantId)-\(amount)" }
}

struct ApiSummary: Decodable {
    let totalExpense: Int
    let balances: [BalanceRow]
    let settlements: [SettlementRow]
}

struct ApiPhoto: Decodable, Identifiable {
    let id: String
    let caption: String
    /// Base64 anh thu nho; luoi anh chi doc field nay cho nhe.
    let thumbData: String
    let createdAt: String
}

struct PhotoInput: Encodable {
    var mimeType = "image/jpeg"
    var data: String
    var thumbData: String
    var width: Int
    var height: Int
    var caption = ""
}

struct ApiShareLink: Decodable {
    let token: String
    let enabled: Bool
}

struct ApiCollaborator: Decodable, Identifiable {
    let userId: String?
    let name: String
    let email: String

    var id: String { userId ?? email }
}

struct ApiShareCandidate: Decodable, Identifiable {
    let id: String
    let name: String
    let email: String
}

struct ApiGameDetail: Decodable {
    let id: String
    let code: String
    let name: String
    let settlementMode: String
    let settlementHostId: String
    let closedAt: String?
    let closeMode: String
    let participants: [ApiParticipant]
    let expenses: [ApiExpense]
    let summary: ApiSummary
    let shareLink: ApiShareLink?
    let isOwner: Bool
    let collaborators: [ApiCollaborator]

    var isClosed: Bool { closedAt != nil }

    func name(of participantId: String) -> String {
        participants.first { $0.id == participantId }?.name ?? "?"
    }
}

/// Payload cua POST /api/games/:id/expenses, mode "equal" (xem expenseInputSchema).
struct ExpenseInput: Encodable {
    var kind = "expense"
    var category = ""
    var title: String
    var amount: Int
    var note: String = ""
    var payerParticipantId: String
    var splitMode = "equal"
    var splitParticipantIds: [String]
}

struct GameInput: Encodable {
    var name: String
    var settlementMode = "p2p"
    var settlementHostId = ""
    var participantCount = 0
}

/// PATCH /api/games/:id — chi gui field muon doi (xem gameUpdateSchema).
struct GameUpdateInput: Encodable {
    var name: String?
    var settlementMode: String?
    var settlementHostId: String?
}

struct PersonInput: Encodable {
    var name: String
    var bankId = ""
    var accountNo = ""
    var accountName = ""
}

struct PeopleInput: Encodable {
    var people: [PersonInput]
}

struct TransferInput: Encodable {
    var fromParticipantId: String
    var toParticipantId: String
    var amount: Int
    var note = ""
}

struct ShuttleEntryInput: Encodable {
    var kind: String
    var quantity: Int
    var note = ""
}

struct ProfileInput: Encodable {
    var name: String
}

struct McpTokenInput: Encodable {
    var name: String
    var scopes: [String]
    var expiresInDays: Int?
}

struct EnabledInput: Encodable {
    var enabled: Bool
}

struct EmailInput: Encodable {
    var email: String
}

struct AiSuggestion: Decodable {
    let title: String
    let amount: Int
    let note: String
    let payerParticipantId: String
    let splitParticipantIds: [String]
}

struct AiSuggestionResponse: Decodable {
    let suggestion: AiSuggestion
}

struct ReceiptInput: Encodable {
    struct Image: Encodable {
        let mimeType = "image/jpeg"
        let data: String
    }
    let gameId: String
    let image: Image
}

struct ApiTrashGame: Decodable, Identifiable {
    let id: String
    let code: String
    let name: String
    let deletedAt: String
}

/// Vai endpoint boc ket qua trong mot object mot field thay vi tra array tran.
struct Wrapped<T: Decodable>: Decodable {
    let contacts: T?
    let events: T?

    var value: T? { contacts ?? events }
}

struct ApiContact: Decodable, Identifiable {
    let key: String
    /// id trong bang contacts; nil voi nguoi chi suy ra tu lich su cuoc chia
    /// — nhung nguoi do khong sua/xoa duoc. KHONG dung lam Identifiable.id:
    /// nil trung nhau thi SwiftUI gop het thanh mot dong.
    let contactId: String?
    let name: String
    let bankId: String
    let accountNo: String
    let accountName: String
    let gameCount: Int
    /// "book" sua/xoa duoc; "history" chi suy ra tu cuoc cu.
    let source: String

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, name, bankId, accountNo, accountName, gameCount, source
        case contactId = "id"
    }
}

struct ApiCrossGamePersonGame: Decodable, Identifiable {
    let code: String
    let name: String
    let balance: Int

    var id: String { code }
}

struct ApiCrossGamePerson: Decodable, Identifiable {
    let name: String
    let paid: Int
    let owed: Int
    let net: Int
    let games: [ApiCrossGamePersonGame]

    var id: String { name }
}

struct ApiCrossSettlement: Decodable, Identifiable {
    let from: String
    let to: String
    let amount: Int

    var id: String { "\(from)-\(to)-\(amount)" }
}

struct ApiCrossGameBalances: Decodable {
    let totalExpense: Int
    let omittedGameCount: Int
    let people: [ApiCrossGamePerson]
    let settlements: [ApiCrossSettlement]
    let namesInOneGameOnly: [String]
}

struct ApiFunStatsBadge: Decodable {
    let name: String
    let totalPaid: Int
    let gameCount: Int
}

struct ApiFunStatsExpense: Decodable {
    let title: String
    let amount: Int
    let gameName: String
}

struct ApiFunStatsGame: Decodable {
    let name: String
    let participantCount: Int
}

struct ApiFunStats: Decodable {
    let gameCount: Int
    let totalExpense: Int
    let topPayer: ApiFunStatsBadge?
    let mostActive: ApiFunStatsBadge?
    let biggestExpense: ApiFunStatsExpense?
    let biggestGame: ApiFunStatsGame?
    /// 0 = Chu nhat, giong Date.getDay() ben JS.
    let favoriteWeekday: Int?
    let omittedGameCount: Int
}

struct ApiShuttleEntry: Decodable, Identifiable {
    let id: String
    let kind: String
    let delta: Int
    let stockAfter: Int
    let note: String
    let createdAt: String
}

struct ApiShuttleStock: Decodable {
    let stock: Int
    let entries: [ApiShuttleEntry]
}

struct ApiMcpToken: Decodable, Identifiable {
    let id: String
    let name: String
    let tokenPrefix: String
    let scopes: [String]
    let createdAt: String
    let expiresAt: String?
    let active: Bool
}

struct ApiCreatedMcpToken: Decodable {
    let token: ApiMcpToken
    let secret: String
}

struct ApiSessionUser: Decodable {
    let id: String
    let name: String
    let image: String?
}

struct ApiSession: Decodable {
    let user: ApiSessionUser?
}

struct ApiShareLinkOnly: Decodable {
    let token: String
    let enabled: Bool
}

/**
 * Mot dong lich su. Ben web `payload` la union 13 nhanh; o day go thanh MOT
 * struct toan field optional. Doi lay: khong phai viet 13 nhanh Codable, va
 * server them nhanh moi thi app hien chung chung chu khong vo.
 */
struct ApiGameEventPayload: Decodable {
    let kind: String
    let name: String?
    let from: String?
    let to: String?
    let title: String?
    let amount: Int?
    let payerName: String?
    let fromName: String?
    let toName: String?
    let names: [String]?
    let splitNames: [String]?
    let hostName: String?
    let mode: String?
}

struct ApiGameEvent: Decodable, Identifiable {
    let id: String
    let createdAt: String
    let undoneAt: String?
    let payload: ApiGameEventPayload
}

enum ApiError: LocalizedError {
    /// Token het han hoac bi thu hoi — goi AuthStore.signOut, dung retry.
    case unauthorized
    case status(Int)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Phiên đã hết hạn"
        case .status(let code): "Máy chủ trả lỗi \(code)"
        case .transport(let message): message
        }
    }
}

struct ApiClient {
    static let origin = "https://chiakeo.huyab.click"

    let token: String
    /// Test tiem URLSession co URLProtocol gia vao day; app dung shared.
    var session: URLSession = .shared

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(request(path, method: "GET"))
    }

    func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await send(json(path, method: "POST", body: body))
    }

    func post<T: Decodable>(_ path: String) async throws -> T {
        try await send(request(path, method: "POST"))
    }

    func patch<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        try await send(json(path, method: "PATCH", body: body))
    }

    /// Endpoint chi doi trang thai (close, reopen, delete...) — bo qua body tra ve.
    func fire(_ path: String, method: String) async throws {
        _ = try await send(request(path, method: method)) as Ignored
    }

    private func json(_ path: String, method: String, body: some Encodable) throws -> URLRequest {
        var req = request(path, method: method)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return req
    }

    private func request(_ path: String, method: String) -> URLRequest {
        var req = URLRequest(url: URL(string: Self.origin + path)!)
        req.httpMethod = method
        // Bearer chu khong phai header Cookie: cookie jar cua URLSession hay chen
        // ngang, va worker doc ca hai (xem worker/src/sso.ts readSsoToken).
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    /// Nuot moi thu, ke ca body rong — dung cho request chi can biet 2xx.
    struct Ignored: Decodable {
        init() {}
        init(from decoder: Decoder) throws {}
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ApiError.transport(error.localizedDescription)
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw ApiError.unauthorized }
        guard (200..<300).contains(code) else { throw ApiError.status(code) }

        if T.self == Ignored.self { return Ignored() as! T }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            #if DEBUG
            throw ApiError.transport("Không đọc được dữ liệu: \(error)")
            #else
            throw ApiError.transport("Dữ liệu trả về không đọc được")
            #endif
        }
    }
}

/// "125000" -> "125.000 ₫". Khong dung currency style cua Locale: may nguoi de
/// may tieng Anh thi ra "₫125,000", doc rat nguoc voi nguoi Viet.
func formatVnd(_ amount: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = "."
    formatter.maximumFractionDigits = 0
    let digits = formatter.string(from: NSNumber(value: abs(amount))) ?? "\(abs(amount))"
    return (amount < 0 ? "-" : "") + digits + " ₫"
}

/// Ngay tu server la ISO; hien "12 thg 8". Chuoi la thi tra ve nguyen ban chu
/// khong bo trong — thay chuoi la con de doan hon la thay o trong.
func formatShortDate(_ iso: String) -> String {
    guard let date = parseIso(iso) else { return iso }

    let out = DateFormatter()
    out.locale = Locale(identifier: "vi_VN")
    out.setLocalizedDateFormatFromTemplate("d MMM")
    return out.string(from: date)
}

// MARK: - Nhan tieng Viet

/// Danh muc chi tieu, khop shared/expense-categories.ts. "" la chua phan loai.
let expenseCategories: [(id: String, label: String, emoji: String)] = [
    ("food", "Ăn uống", "🍜"),
    ("drink", "Cà phê, nhậu", "🍻"),
    ("transport", "Đi lại", "🚕"),
    ("stay", "Chỗ ở", "🏨"),
    ("fun", "Vui chơi", "🎡"),
    ("shopping", "Mua sắm", "🛍️"),
    ("health", "Thuốc men", "💊"),
    ("other", "Khác", "📦"),
]

func categoryEmoji(_ id: String) -> String {
    expenseCategories.first { $0.id == id }?.emoji ?? "❔"
}

func categoryLabel(_ id: String) -> String {
    expenseCategories.first { $0.id == id }?.label ?? "Chưa phân loại"
}

/// Che do chuyen tien, khop settlementModeSchema.
let settlementModes: [(id: String, label: String)] = [
    ("p2p", "Ai nợ ai trả người đó"),
    ("host", "Gom về người ứng nhiều nhất"),
    ("pick", "Gom về một người tự chọn"),
    ("off", "Không gợi ý chuyển tiền"),
]

func settlementLabel(_ id: String) -> String {
    settlementModes.first { $0.id == id }?.label ?? id
}

let mcpScopeLabels: [(id: String, label: String)] = [
    ("games:read", "Xem cuộc chia"),
    ("summary:read", "Xem tổng kết"),
    ("share:read", "Xem link chia sẻ"),
]

/// 0 = Chu nhat, giong Date.getDay() ben JS.
func weekdayName(_ day: Int) -> String {
    let names = ["Chủ nhật", "Thứ hai", "Thứ ba", "Thứ tư", "Thứ năm", "Thứ sáu", "Thứ bảy"]
    return names.indices.contains(day) ? names[day] : "?"
}

/// "12 thg 8, 19:30". Chuoi la tra ve nguyen ban, nhu formatShortDate.
func formatDateTime(_ iso: String) -> String {
    guard let date = parseIso(iso) else { return iso }
    let out = DateFormatter()
    out.locale = Locale(identifier: "vi_VN")
    out.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
    return out.string(from: date)
}

func parseIso(_ iso: String) -> Date? {
    let parsers = [ISO8601DateFormatter(), {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()]
    return parsers.lazy.compactMap { $0.date(from: iso) }.first
}

/// Mot dong lich su bang tieng Viet. Nhanh la (server them kind moi) hien
/// chinh chuoi kind chu khong bo trong — de con biet co viec gi da xay ra.
func describeEvent(_ payload: ApiGameEventPayload) -> String {
    let money = payload.amount.map(formatVnd) ?? ""
    switch payload.kind {
    case "game_created": return "Tạo cuộc \"\(payload.name ?? "")\""
    case "game_renamed": return "Đổi tên: \(payload.from ?? "") → \(payload.to ?? "")"
    case "settlement_changed":
        let mode = settlementLabel(payload.mode ?? "")
        return payload.hostName.map { "Chuyển tiền: \(mode) · \($0)" } ?? "Chuyển tiền: \(mode)"
    case "participant_added": return "Thêm người: \((payload.names ?? []).joined(separator: ", "))"
    case "participant_renamed": return "Đổi tên người: \(payload.from ?? "") → \(payload.to ?? "")"
    case "participant_removed": return "Xoá người: \(payload.name ?? "")"
    case "expense_added":
        let who = payload.payerName ?? ""
        return "Thêm chi \"\(payload.title ?? "")\" \(money) · \(who) ứng"
    case "expense_updated": return "Sửa chi \"\(payload.title ?? "")\" \(money)"
    case "expense_removed": return "Xoá chi \"\(payload.title ?? "")\" \(money)"
    case "expense_restored": return "Hoàn tác xoá \"\(payload.title ?? "")\" \(money)"
    case "transfer_added":
        return "Chuyển tiền: \(payload.fromName ?? "") → \(payload.toName ?? "") \(money)"
    case "game_closed": return "Đóng cuộc chia"
    case "game_reopened": return "Mở lại cuộc chia"
    default: return payload.kind
    }
}
