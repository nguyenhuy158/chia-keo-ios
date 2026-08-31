import Foundation

/// Ban chieu cua shared/summary-text.ts. Copy la tinh nang hay dung nhat, nen
/// text phai giong y ban web de dan vao Zalo/Messenger doc quen mat.
enum SummaryVariant {
    case compact, detailed
}

private let unknownName = "Không rõ"

private let thousandsFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal            // vi-VN: "1.043" chu khong "1043"
    formatter.locale = Locale(identifier: "vi_VN")
    formatter.maximumFractionDigits = 1
    return formatter
}()

/// 90000 -> "90", 8500 -> "8,5", 1043000 -> "1.043". Don vi nghin dong.
func formatThousands(_ value: Int) -> String {
    let rounded = (Double(value) / 100).rounded() / 10
    return thousandsFormatter.string(from: rounded as NSNumber) ?? "\(rounded)"
}

func formatShortMoney(_ value: Int) -> String { "\(formatThousands(value))k" }

/// Nguoi ung nhieu nhat; "" khi chua co ai.
func pickHostParticipantId(_ balances: [BalanceRow]) -> String {
    balances.max { $0.balance < $1.balance }?.participantId ?? ""
}

/// "host" tu chon nguoi ung nhieu nhat; "pick" lay nguoi da chon nhung chi khi
/// nguoi do con trong cuoc. Che do khac tra ve "".
func resolveHostParticipantId(_ balances: [BalanceRow], mode: String, hostId: String) -> String {
    guard mode == "host" || mode == "pick" else { return "" }
    if mode == "pick", !hostId.isEmpty, balances.contains(where: { $0.participantId == hostId }) {
        return hostId
    }
    return pickHostParticipantId(balances)
}

/// Mot phan cua ban tom tat, de text va anh dung chung noi dung.
struct SummaryBlock {
    let heading: String
    let lines: [String]
}

struct SummaryDoc {
    let title: String
    let subtitle: String
    let sections: [SummaryBlock]
    let footer: String?
}

/// Text va anh cung dung mot noi dung: sua o day la sua ca hai.
func buildSummaryDoc(_ detail: ApiGameDetail,
                     variant: SummaryVariant = .compact,
                     shareUrl: String? = nil) -> SummaryDoc {
    let detailed = variant == .detailed
    // API tra khoan moi nhat truoc; doc bang chu thi de theo tu khoan cu nhat.
    // Khoan tra no da vao balance nen khong liet ke chung voi cac khoan chi.
    let expenses = detail.expenses.filter { $0.kind != "transfer" }.reversed().map { $0 }
    let balanceById = Dictionary(uniqueKeysWithValues: detail.summary.balances.map { ($0.participantId, $0) })
    func name(_ id: String) -> String { detail.participants.first { $0.id == id }?.name ?? unknownName }

    var sections: [SummaryBlock] = []

    // MARK: Cac khoan chi
    let chiHeading = expenses.isEmpty
        ? "CÁC KHOẢN CHI"
        : "CÁC KHOẢN CHI (\(expenses.count) khoản · tổng \(formatShortMoney(detail.summary.totalExpense)))"
    var chi: [String] = []
    if expenses.isEmpty {
        chi.append("Chưa có khoản chi nào.")
    } else {
        for (index, expense) in expenses.enumerated() {
            let splits = expense.splits ?? []
            let who = splits.count > 0 && splits.count == detail.participants.count
                ? "cả nhóm"
                : splits.map { name($0.participantId) }.joined(separator: ", ")
            var line = "\(index + 1). \(expense.title) (\(name(expense.payerParticipantId)) trả)"
                + " — \(describeSplit(expense, name: name))"
            if !who.isEmpty { line += " · (\(who))" }
            chi.append(line)
        }
    }
    sections.append(SummaryBlock(heading: chiHeading, lines: chi))

    // MARK: Tung nguoi
    if !detail.participants.isEmpty {
        var nguoi: [String] = []
        for participant in detail.participants {
            let terms = expenses.compactMap { expense -> String? in
                guard let share = (expense.splits ?? []).first(where: { $0.participantId == participant.id }),
                      share.amount > 0 else { return nil }
                return formatThousands(share.amount)
            }
            let row = balanceById[participant.id]
            var line = terms.isEmpty
                ? "- \(participant.name): 0k"
                : "- \(participant.name): \(terms.joined(separator: " + ")) = \(formatShortMoney(row?.owed ?? 0))"
            if detailed, let state = describeSettleState(row) { line += " · \(state)" }
            nguoi.append(line)
        }
        sections.append(SummaryBlock(heading: detailed ? "TỪNG NGƯỜI (phần phải chịu)" : "TỪNG NGƯỜI",
                                      lines: nguoi))
    }

    // MARK: Chuyen tien
    let mode = detail.settlementMode
    if mode == "host" || mode == "pick" {
        let hostId = resolveHostParticipantId(detail.summary.balances, mode: mode, hostId: detail.settlementHostId)
        let transfers = detail.summary.balances.filter { $0.participantId != hostId && $0.balance != 0 }
        if !hostId.isEmpty, !transfers.isEmpty {
            sections.append(hostSection(transfers, hostName: name(hostId), hostId: hostId,
                                        balances: detail.summary.balances, detailed: detailed, name: name))
        }
    } else if mode != "off", !detail.summary.settlements.isEmpty {
        sections.append(SummaryBlock(heading: "CẦN CHUYỂN", lines: detail.summary.settlements.map {
            "- \(name($0.fromParticipantId)) → \(name($0.toParticipantId)): \(formatShortMoney($0.amount))"
        }))
    }

    return SummaryDoc(title: detail.name, subtitle: detail.code, sections: sections,
                      footer: shareUrl.map { "Chi tiết: \($0)" })
}

func buildSummaryText(_ detail: ApiGameDetail,
                      variant: SummaryVariant = .compact,
                      shareUrl: String? = nil) -> String {
    let doc = buildSummaryDoc(detail, variant: variant, shareUrl: shareUrl)
    var blocks = ["\(doc.title) · \(doc.subtitle)"]
    blocks += doc.sections.map { ([$0.heading] + $0.lines).joined(separator: "\n") }
    if let footer = doc.footer { blocks.append(footer) }
    return blocks.joined(separator: "\n\n")
}

/// Viet nhu phep tinh nham kiem lai duoc: chia deu "425/5 = 85k", chia tuy
/// chinh "305k = 5 (Huy) + 200 (Kiệt)", mot nguoi thi bo han phep chia.
private func describeSplit(_ expense: ApiExpense, name: (String) -> String) -> String {
    let splits = expense.splits ?? []
    let total = formatShortMoney(expense.amount)
    guard splits.count > 1 else { return total }

    if expense.splitMode != "equal" {
        let shares = splits.map { "\(formatThousands($0.amount)) (\(name($0.participantId)))" }
        return "\(total) = \(shares.joined(separator: " + "))"
    }
    return "\(formatThousands(expense.amount))/\(splits.count)"
        + " = \(formatShortMoney(expense.amount / splits.count))"
}

/// Thieu cau nay thi so "phai chiu" de bi doc thanh "phai chuyen", du nguoi ung
/// tien la nguoi duoc nhan lai.
private func describeSettleState(_ row: BalanceRow?) -> String? {
    guard let row else { return nil }
    if row.balance > 0 {
        return "đã ứng \(formatShortMoney(row.paid)) → nhận lại \(formatShortMoney(row.balance))"
    }
    if row.balance < 0 { return "phải trả \(formatShortMoney(-row.balance))" }
    return row.paid > 0 ? "đã ứng \(formatShortMoney(row.paid)) → vừa đủ" : nil
}

private func hostSection(_ transfers: [BalanceRow], hostName: String, hostId: String,
                         balances: [BalanceRow], detailed: Bool,
                         name: (String) -> String) -> SummaryBlock {
    guard detailed else {
        // Ban goc: mot danh sach phang, giu dung thu tu nguoi tham gia.
        let lines = transfers.map { row in
            row.balance < 0
                ? "- \(name(row.participantId)) → \(hostName): \(formatShortMoney(-row.balance))"
                : "- \(hostName) → \(name(row.participantId)): \(formatShortMoney(row.balance))"
        }
        return SummaryBlock(heading: "GOM VỀ \(hostName.uppercased())", lines: lines)
    }

    // Ban chi tiet: tach hai chieu, kem tong tien vao va ly do host tra lai.
    let reason = hostId == pickHostParticipantId(balances)
        ? "\(hostName) ứng nhiều nhất, cả nhóm quét 1 QR"
        : "cả nhóm quét 1 QR"
    var lines: [String] = []

    let incoming = transfers.filter { $0.balance < 0 }
    if !incoming.isEmpty {
        let total = incoming.reduce(0) { $0 - $1.balance }
        lines.append("Chuyển vào \(hostName) — tổng \(formatShortMoney(total)):")
        lines += incoming.map {
            "- \(name($0.participantId)) → \(hostName): \(formatShortMoney(-$0.balance))"
        }
    }

    let outgoing = transfers.filter { $0.balance > 0 }
    if !outgoing.isEmpty {
        lines.append("\(hostName) chuyển ra:")
        lines += outgoing.map { row in
            let why = row.paid > 0
                ? " (\(name(row.participantId)) đã ứng \(formatShortMoney(row.paid)))"
                : ""
            return "- \(hostName) → \(name(row.participantId)): \(formatShortMoney(row.balance))\(why)"
        }
    }
    return SummaryBlock(heading: "GOM VỀ \(hostName.uppercased()) (\(reason))", lines: lines)
}
