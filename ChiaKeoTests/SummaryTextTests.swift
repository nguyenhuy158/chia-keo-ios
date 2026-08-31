import XCTest
@testable import ChiaKeo

/// Text copy la thu nguoi dung dan vao Zalo, sai mot dong la sai het — nen so
/// khop tung dong voi ban web (shared/summary-text.ts).
final class SummaryTextTests: XCTestCase {
    private func detail(mode: String = "p2p", hostId: String = "") throws -> ApiGameDetail {
        let json = """
        {"id":"g1","code":"ABC","name":"Cầu tối","settlementMode":"\(mode)",
         "settlementHostId":"\(hostId)","closedAt":null,"closeMode":"manual",
         "participants":[{"id":"p1","name":"Huy","bankId":"","accountNo":"","accountName":""},
                         {"id":"p2","name":"Kiệt","bankId":"","accountNo":"","accountName":""}],
         "expenses":[
           {"id":"e2","kind":"expense","category":"","title":"Nước","amount":8500,"note":"",
            "payerParticipantId":"p2","splitMode":"custom",
            "splitParticipantIds":["p1","p2"],
            "splits":[{"participantId":"p1","amount":8500},{"participantId":"p2","amount":0}],
            "createdAt":"2025-08-12T13:00:00Z"},
           {"id":"e1","kind":"expense","category":"","title":"Cầu","amount":120000,"note":"",
            "payerParticipantId":"p1","splitMode":"equal",
            "splitParticipantIds":["p1","p2"],
            "splits":[{"participantId":"p1","amount":60000},{"participantId":"p2","amount":60000}],
            "createdAt":"2025-08-12T12:00:00Z"},
           {"id":"t1","kind":"transfer","category":"","title":"Trả nợ","amount":1000,"note":"",
            "payerParticipantId":"p2","splitMode":"equal","splitParticipantIds":["p1"],
            "splits":[{"participantId":"p1","amount":1000}],
            "createdAt":"2025-08-12T14:00:00Z"}],
         "summary":{"totalExpense":128500,
           "balances":[{"participantId":"p1","paid":120000,"owed":68500,"balance":51500},
                       {"participantId":"p2","paid":8500,"owed":60000,"balance":-51500}],
           "settlements":[{"fromParticipantId":"p2","toParticipantId":"p1","amount":51500}]},
         "shareLink":null,"isOwner":true,"collaborators":[]}
        """
        return try JSONDecoder().decode(ApiGameDetail.self, from: Data(json.utf8))
    }

    func testMoneyFormat() {
        XCTAssertEqual(formatThousands(90_000), "90")
        XCTAssertEqual(formatThousands(8_500), "8,5")
        XCTAssertEqual(formatThousands(1_043_000), "1.043")
        XCTAssertEqual(formatShortMoney(85_000), "85k")
    }

    func testCompact() throws {
        // Khoan cu nhat len truoc, khoan tra no khong duoc liet ke.
        XCTAssertEqual(buildSummaryText(try detail()), """
        Cầu tối · ABC

        CÁC KHOẢN CHI (2 khoản · tổng 128,5k)
        1. Cầu (Huy trả) — 120/2 = 60k · (cả nhóm)
        2. Nước (Kiệt trả) — 8,5k = 8,5 (Huy) + 0 (Kiệt) · (cả nhóm)

        TỪNG NGƯỜI
        - Huy: 60 + 8,5 = 68,5k
        - Kiệt: 60 = 60k

        CẦN CHUYỂN
        - Kiệt → Huy: 51,5k
        """)
    }

    func testDetailedAddsSettleState() throws {
        let text = buildSummaryText(try detail(), variant: .detailed, shareUrl: "https://x/y")
        XCTAssertTrue(text.contains("TỪNG NGƯỜI (phần phải chịu)"))
        XCTAssertTrue(text.contains("- Huy: 60 + 8,5 = 68,5k · đã ứng 120k → nhận lại 51,5k"))
        XCTAssertTrue(text.contains("- Kiệt: 60 = 60k · phải trả 51,5k"))
        XCTAssertTrue(text.hasSuffix("Chi tiết: https://x/y"))
    }

    func testHostModeFlatAndGrouped() throws {
        let flat = buildSummaryText(try detail(mode: "host"))
        XCTAssertTrue(flat.contains("GOM VỀ HUY\n- Kiệt → Huy: 51,5k"), flat)

        let grouped = buildSummaryText(try detail(mode: "host"), variant: .detailed)
        XCTAssertTrue(grouped.contains("GOM VỀ HUY (Huy ứng nhiều nhất, cả nhóm quét 1 QR)"), grouped)
        XCTAssertTrue(grouped.contains("Chuyển vào Huy — tổng 51,5k:"), grouped)

        // "pick" chon nguoi khong ung nhieu nhat thi bo cau "ứng nhiều nhất".
        let picked = buildSummaryText(try detail(mode: "pick", hostId: "p2"), variant: .detailed)
        XCTAssertTrue(picked.contains("GOM VỀ KIỆT (cả nhóm quét 1 QR)"), picked)
        XCTAssertTrue(picked.contains("Kiệt chuyển ra:"), picked)
        XCTAssertTrue(picked.contains("- Kiệt → Huy: 51,5k (Huy đã ứng 120k)"), picked)
    }

    func testOffModeHasNoTransferBlock() throws {
        let text = buildSummaryText(try detail(mode: "off"))
        XCTAssertFalse(text.contains("CẦN CHUYỂN"))
        XCTAssertFalse(text.contains("GOM VỀ"))
    }

    func testEmptyGame() throws {
        let empty = try JSONDecoder().decode(ApiGameDetail.self, from: Data("""
        {"id":"g","code":"C","name":"Trống","settlementMode":"p2p","settlementHostId":"",
         "closedAt":null,"closeMode":"manual","participants":[],"expenses":[],
         "summary":{"totalExpense":0,"balances":[],"settlements":[]},
         "shareLink":null,"isOwner":true,"collaborators":[]}
        """.utf8))
        XCTAssertEqual(buildSummaryText(empty), "Trống · C\n\nCÁC KHOẢN CHI\nChưa có khoản chi nào.")
    }

    func testResolveHost() {
        let balances = [BalanceRow(participantId: "p1", paid: 0, owed: 0, balance: 10),
                        BalanceRow(participantId: "p2", paid: 0, owed: 0, balance: -10)]
        XCTAssertEqual(resolveHostParticipantId(balances, mode: "p2p", hostId: "p2"), "")
        XCTAssertEqual(resolveHostParticipantId(balances, mode: "host", hostId: "p2"), "p1")
        XCTAssertEqual(resolveHostParticipantId(balances, mode: "pick", hostId: "p2"), "p2")
        // Nguoi da chon bi xoa khoi cuoc -> quay ve nguoi ung nhieu nhat.
        XCTAssertEqual(resolveHostParticipantId(balances, mode: "pick", hostId: "xx"), "p1")
        XCTAssertEqual(pickHostParticipantId([]), "")
    }
}
