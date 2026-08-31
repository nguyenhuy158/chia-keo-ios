import XCTest
@testable import ChiaKeo

/// DTO la ban chieu cua shared/api-types.ts. Test o day giu hai giao uoc:
/// field la KHONG lam vo decode, va field app dung phai doc dung.
final class DecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testGameIgnoresUnknownFields() throws {
        let game = try decode(ApiGame.self, """
        {"id":"g1","code":"ABC","name":"Cầu tối","createdAt":"2025-08-12T12:00:00Z",
         "participantCount":4,"expenseCount":2,"closedAt":null,"closeMode":"manual",
         "isOwner":true,"fieldServerMoiThem":123}
        """)
        XCTAssertEqual(game.id, "g1")
        XCTAssertEqual(game.participantCount, 4)
        XCTAssertNil(game.closedAt)
        XCTAssertTrue(game.isOwner)
    }

    func testGameDetail() throws {
        let detail = try decode(ApiGameDetail.self, """
        {"id":"g1","code":"ABC","name":"Cầu","settlementMode":"p2p","settlementHostId":"",
         "closedAt":"2025-08-13T00:00:00Z","closeMode":"manual",
         "participants":[{"id":"p1","name":"Huy","bankId":"TCB","accountNo":"1","accountName":"HUY"},
                         {"id":"p2","name":"Kiệt","bankId":"","accountNo":"","accountName":""}],
         "expenses":[{"id":"e1","kind":"expense","category":"food","title":"Cầu","amount":120000,
                      "note":"","payerParticipantId":"p1","splitMode":"equal",
                      "splitParticipantIds":["p1","p2"],"createdAt":"2025-08-12T12:00:00Z"}],
         "summary":{"totalExpense":120000,
                    "balances":[{"participantId":"p1","paid":120000,"owed":60000,"balance":60000}],
                    "settlements":[{"fromParticipantId":"p2","toParticipantId":"p1","amount":60000}]},
         "shareLink":{"token":"t","enabled":true},"isOwner":false,
         "collaborators":[{"userId":null,"name":"Ai do","email":"a@b.c"}]}
        """)
        XCTAssertTrue(detail.isClosed)
        XCTAssertEqual(detail.name(of: "p2"), "Kiệt")
        XCTAssertEqual(detail.name(of: "khong-co"), "?")
        XCTAssertEqual(detail.summary.settlements.first?.id, "p2-p1-60000")
        XCTAssertEqual(detail.collaborators.first?.id, "a@b.c")   // userId nil thi lay email
        XCTAssertTrue(detail.shareLink?.enabled ?? false)
    }

    func testGameDetailOpenGame() throws {
        let detail = try decode(ApiGameDetail.self, """
        {"id":"g","code":"C","name":"n","settlementMode":"host","settlementHostId":"p1",
         "closedAt":null,"closeMode":"manual","participants":[],"expenses":[],
         "summary":{"totalExpense":0,"balances":[],"settlements":[]},
         "shareLink":null,"isOwner":true,"collaborators":[]}
        """)
        XCTAssertFalse(detail.isClosed)
        XCTAssertNil(detail.shareLink)
    }

    /// Hoi quy: `id` cua ApiContact phai la `key`. Truoc day lay id trong DB
    /// (nil voi nguoi suy tu lich su) nen ForEach gop het thanh mot dong.
    func testContactIdentityIsKeyNotDatabaseId() throws {
        let contacts = try decode([ApiContact].self, """
        [{"key":"huy","id":"c1","name":"Huy","bankId":"TCB","accountNo":"1","accountName":"HUY",
          "gameCount":3,"source":"book"},
         {"key":"kiet","id":null,"name":"Kiệt","bankId":"","accountNo":"","accountName":"",
          "gameCount":7,"source":"history"},
         {"key":"nam","id":null,"name":"Nam","bankId":"","accountNo":"","accountName":"",
          "gameCount":1,"source":"history"}]
        """)
        XCTAssertEqual(contacts.map(\.id), ["huy", "kiet", "nam"])
        XCTAssertEqual(Set(contacts.map(\.id)).count, 3)
        XCTAssertEqual(contacts[0].contactId, "c1")
        XCTAssertNil(contacts[1].contactId)                       // khong sua/xoa duoc
    }

    func testWrappedResponses() throws {
        let contacts = try decode(Wrapped<[ApiContact]>.self, """
        {"contacts":[{"key":"huy","id":null,"name":"Huy","bankId":"","accountNo":"",
                      "accountName":"","gameCount":1,"source":"history"}]}
        """)
        XCTAssertEqual(contacts.value?.count, 1)

        let events = try decode(Wrapped<[ApiGameEvent]>.self, """
        {"events":[{"id":"ev1","createdAt":"2025-08-12T12:00:00Z","undoneAt":null,
                    "payload":{"kind":"game_closed"}}]}
        """)
        XCTAssertEqual(events.value?.first?.id, "ev1")
        XCTAssertNil(events.value?.first?.undoneAt)

        let empty = try decode(Wrapped<[ApiContact]>.self, "{}")
        XCTAssertNil(empty.value)
    }

    func testCrossGameBalances() throws {
        let cross = try decode(ApiCrossGameBalances.self, """
        {"totalExpense":300000,"omittedGameCount":1,
         "people":[{"name":"Huy","paid":300000,"owed":100000,"net":200000,
                    "games":[{"code":"ABC","name":"Cầu","balance":200000}]}],
         "settlements":[{"from":"Kiệt","to":"Huy","amount":100000}],
         "namesInOneGameOnly":["Nam"]}
        """)
        XCTAssertEqual(cross.people.first?.id, "Huy")
        XCTAssertEqual(cross.people.first?.games.first?.id, "ABC")
        XCTAssertEqual(cross.settlements.first?.id, "Kiệt-Huy-100000")
        XCTAssertEqual(cross.namesInOneGameOnly, ["Nam"])
    }

    func testFunStatsAllNil() throws {
        let stats = try decode(ApiFunStats.self, """
        {"gameCount":0,"totalExpense":0,"topPayer":null,"mostActive":null,
         "biggestExpense":null,"biggestGame":null,"favoriteWeekday":null,"omittedGameCount":0}
        """)
        XCTAssertNil(stats.topPayer)
        XCTAssertNil(stats.favoriteWeekday)
    }

    func testFunStatsFull() throws {
        let stats = try decode(ApiFunStats.self, """
        {"gameCount":5,"totalExpense":900000,
         "topPayer":{"name":"Huy","totalPaid":500000,"gameCount":5},
         "mostActive":{"name":"Kiệt","totalPaid":100000,"gameCount":5},
         "biggestExpense":{"title":"Cầu","amount":200000,"gameName":"Cầu tối"},
         "biggestGame":{"name":"Cầu tối","participantCount":8},
         "favoriteWeekday":3,"omittedGameCount":0}
        """)
        XCTAssertEqual(stats.topPayer?.name, "Huy")
        XCTAssertEqual(weekdayName(stats.favoriteWeekday ?? -1), "Thứ tư")
        XCTAssertEqual(stats.biggestGame?.participantCount, 8)
    }

    func testShuttleStock() throws {
        let stock = try decode(ApiShuttleStock.self, """
        {"stock":12,"entries":[{"id":"s1","kind":"add","delta":6,"stockAfter":12,
                                "note":"mua","createdAt":"2025-08-12T12:00:00Z"}]}
        """)
        XCTAssertEqual(stock.stock, 12)
        XCTAssertEqual(stock.entries.first?.delta, 6)
    }

    func testMcpTokens() throws {
        let created = try decode(ApiCreatedMcpToken.self, """
        {"token":{"id":"m1","name":"Claude","tokenPrefix":"ck_ab","scopes":["games:read"],
                  "createdAt":"2025-08-12T12:00:00Z","expiresAt":null,"active":true},
         "secret":"ck_ab_secret"}
        """)
        XCTAssertEqual(created.secret, "ck_ab_secret")
        XCTAssertEqual(created.token.scopes, ["games:read"])
        XCTAssertNil(created.token.expiresAt)
    }

    func testSessionAndTrashAndPhoto() throws {
        XCTAssertEqual(try decode(ApiSession.self,
            "{\"user\":{\"id\":\"u1\",\"name\":\"Huy\",\"image\":null}}").user?.name, "Huy")
        XCTAssertNil(try decode(ApiSession.self, "{\"user\":null}").user)

        let trash = try decode([ApiTrashGame].self,
            "[{\"id\":\"g1\",\"code\":\"ABC\",\"name\":\"Cũ\",\"deletedAt\":\"2025-08-12T12:00:00Z\"}]")
        XCTAssertEqual(trash.first?.name, "Cũ")

        let photo = try decode(ApiPhoto.self,
            "{\"id\":\"ph1\",\"caption\":\"hoá đơn\",\"thumbData\":\"AAA\",\"createdAt\":\"2025-08-12T12:00:00Z\"}")
        XCTAssertEqual(photo.thumbData, "AAA")
    }

    func testAiSuggestion() throws {
        let response = try decode(AiSuggestionResponse.self, """
        {"suggestion":{"title":"Cầu","amount":120000,"note":"","payerParticipantId":"p1",
                       "splitParticipantIds":["p1","p2"]}}
        """)
        XCTAssertEqual(response.suggestion.amount, 120000)
    }

    func testShareCandidate() throws {
        let candidates = try decode([ApiShareCandidate].self,
            "[{\"id\":\"u1\",\"name\":\"Huy\",\"email\":\"a@b.c\"}]")
        XCTAssertEqual(candidates.first?.id, "u1")
    }

    // MARK: - Input encode dung khoa server doi

    func testInputsEncodeExpectedKeys() throws {
        func keys(_ value: some Encodable) throws -> [String: Any] {
            let data = try JSONEncoder().encode(value)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        }

        let expense = try keys(ExpenseInput(title: "Cầu", amount: 120000,
                                            payerParticipantId: "p1", splitParticipantIds: ["p1"]))
        XCTAssertEqual(expense["kind"] as? String, "expense")
        XCTAssertEqual(expense["splitMode"] as? String, "equal")
        XCTAssertEqual(expense["category"] as? String, "")

        let game = try keys(GameInput(name: "Cầu tối"))
        XCTAssertEqual(game["settlementMode"] as? String, "p2p")

        // GameUpdateInput chi gui field duoc dat — field nil bi bo hoan toan.
        let update = try keys(GameUpdateInput(name: "Tên mới"))
        XCTAssertEqual(update.count, 1)
        XCTAssertEqual(update["name"] as? String, "Tên mới")

        let people = try keys(PeopleInput(people: [PersonInput(name: "Huy")]))
        XCTAssertEqual((people["people"] as? [[String: Any]])?.first?["bankId"] as? String, "")

        let transfer = try keys(TransferInput(fromParticipantId: "p1", toParticipantId: "p2", amount: 1000))
        XCTAssertEqual(transfer["note"] as? String, "")

        let photo = try keys(PhotoInput(data: "A", thumbData: "B", width: 100, height: 50))
        XCTAssertEqual(photo["mimeType"] as? String, "image/jpeg")

        let receipt = try keys(ReceiptInput(gameId: "g1", image: .init(data: "A")))
        XCTAssertEqual((receipt["image"] as? [String: Any])?["mimeType"] as? String, "image/jpeg")

        XCTAssertEqual(try keys(EnabledInput(enabled: true))["enabled"] as? Bool, true)
        XCTAssertEqual(try keys(EmailInput(email: "a@b.c"))["email"] as? String, "a@b.c")
        XCTAssertEqual(try keys(ProfileInput(name: "Huy"))["name"] as? String, "Huy")
        XCTAssertEqual(try keys(ShuttleEntryInput(kind: "use", quantity: 2))["quantity"] as? Int, 2)
        XCTAssertEqual(try keys(McpTokenInput(name: "n", scopes: ["games:read"],
                                             expiresInDays: 30))["expiresInDays"] as? Int, 30)
    }
}
