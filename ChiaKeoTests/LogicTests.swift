import XCTest
@testable import ChiaKeo

/// JWT gia: chi phan payload la thuc, chu ky la rac — app khong verify chu ky.
func fakeJwt(exp: TimeInterval?, extra: String = "") -> String {
    var claims = extra
    if let exp { claims += "\"exp\":\(exp)" }
    let payload = Data("{\(claims)}".utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(payload).signature"
}

final class SsoTokenTests: XCTestCase {
    func testExpiryReadsExpClaim() {
        let exp = Date().addingTimeInterval(3600).timeIntervalSince1970.rounded()
        XCTAssertEqual(SsoToken.expiry(fakeJwt(exp: exp))?.timeIntervalSince1970, exp)
    }

    func testExpiryNilOnMalformedToken() {
        XCTAssertNil(SsoToken.expiry("khong-phai-jwt"))
        XCTAssertNil(SsoToken.expiry("a.b.c"))                       // payload khong base64
        XCTAssertNil(SsoToken.expiry("header.\(Data("khong-json".utf8).base64EncodedString()).sig"))
        XCTAssertNil(SsoToken.expiry(fakeJwt(exp: nil)))             // JSON hop le, thieu exp
        XCTAssertNil(SsoToken.expiry(fakeJwt(exp: nil, extra: "\"exp\":\"chuoi\"")))
    }

    func testIsUsable() {
        XCTAssertTrue(SsoToken.isUsable(fakeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970)))
        XCTAssertFalse(SsoToken.isUsable(fakeJwt(exp: Date().addingTimeInterval(-1).timeIntervalSince1970)))
        // Con 30 giay: qua bien do 60 giay nen coi nhu het han.
        XCTAssertFalse(SsoToken.isUsable(fakeJwt(exp: Date().addingTimeInterval(30).timeIntervalSince1970)))
        XCTAssertTrue(SsoToken.isUsable(fakeJwt(exp: Date().addingTimeInterval(30).timeIntervalSince1970), slack: 5))
        XCTAssertFalse(SsoToken.isUsable("rac"))
    }

    func testBase64UrlDecodeHandlesPaddingAndAlphabet() {
        // "-" va "_" phai doi thanh "+" va "/", va tu bu dau "=" con thieu.
        XCTAssertEqual(SsoToken.base64UrlDecode("YQ"), Data("a".utf8))
        XCTAssertEqual(SsoToken.base64UrlDecode("YWJj"), Data("abc".utf8))
        XCTAssertEqual(SsoToken.base64UrlDecode("-_8"), Data([0xFB, 0xFF]))
        XCTAssertNil(SsoToken.base64UrlDecode("!!!!"))
    }
}

final class KeychainTests: XCTestCase {
    override func tearDown() {
        Keychain.clear()
        super.tearDown()
    }

    func testWriteReadClear() {
        Keychain.clear()
        XCTAssertNil(Keychain.read())
        Keychain.write("token-1")
        XCTAssertEqual(Keychain.read(), "token-1")
        Keychain.write("token-2")               // ghi de, khong duplicate item
        XCTAssertEqual(Keychain.read(), "token-2")
        Keychain.clear()
        XCTAssertNil(Keychain.read())
    }
}

final class SsoCookieTests: XCTestCase {
    override func tearDown() {
        SsoCookie.remove()
        super.tearDown()
    }

    func testInstallAndRemove() {
        SsoCookie.remove()
        SsoCookie.install("abc")
        let cookie = HTTPCookieStorage.shared.cookies?.first { $0.name == "huyab_sso" }
        XCTAssertEqual(cookie?.value, "abc")
        XCTAssertEqual(cookie?.domain, ".huyab.click")
        XCTAssertTrue(cookie?.isSecure ?? false)

        SsoCookie.remove()
        XCTAssertNil(HTTPCookieStorage.shared.cookies?.first { $0.name == "huyab_sso" })
    }
}

@MainActor
final class AuthStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Keychain.clear()
        SsoCookie.remove()
    }

    override func tearDown() {
        Keychain.clear()
        SsoCookie.remove()
        super.tearDown()
    }

    private var goodToken: String { fakeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970) }

    func testInitRestoresUsableToken() {
        Keychain.write(goodToken)
        let store = AuthStore()
        XCTAssertNotNil(store.token)
        XCTAssertNotNil(store.client)
        XCTAssertNotNil(HTTPCookieStorage.shared.cookies?.first { $0.name == "huyab_sso" })
    }

    func testInitDropsExpiredToken() {
        Keychain.write(fakeJwt(exp: Date().addingTimeInterval(-10).timeIntervalSince1970))
        let store = AuthStore()
        XCTAssertNil(store.token)
        XCTAssertNil(store.client)
        XCTAssertNil(Keychain.read())           // don luon cho lan sau
    }

    func testSignInSignOut() {
        let store = AuthStore()
        store.notice = "loi cu"
        store.signIn(token: goodToken)
        XCTAssertEqual(store.token, Keychain.read())
        XCTAssertNil(store.notice)

        store.signOut(notice: "het han")
        XCTAssertNil(store.token)
        XCTAssertNil(Keychain.read())
        XCTAssertEqual(store.notice, "het han")
        XCTAssertNil(HTTPCookieStorage.shared.cookies?.first { $0.name == "huyab_sso" })
    }

    func testPerformWithoutClientDoesNothing() async {
        let store = AuthStore()
        var ran = false
        let error = await store.perform { _ in ran = true }
        XCTAssertNil(error)
        XCTAssertFalse(ran)
    }

    func testPerformSuccessReturnsNil() async {
        let store = AuthStore()
        store.signIn(token: goodToken)
        var ran = false
        let error = await store.perform { _ in ran = true }
        XCTAssertNil(error)
        XCTAssertTrue(ran)
    }

    func testPerformUnauthorizedSignsOut() async {
        let store = AuthStore()
        store.signIn(token: goodToken)
        let error = await store.perform { _ in throw ApiError.unauthorized }
        XCTAssertNil(error)
        XCTAssertNil(store.token)
        XCTAssertEqual(store.notice, "Phiên đã hết hạn, đăng nhập lại nhé.")
    }

    func testPerformOtherErrorReturnsMessage() async {
        let store = AuthStore()
        store.signIn(token: goodToken)
        let error = await store.perform { _ in throw ApiError.status(500) }
        XCTAssertEqual(error, ApiError.status(500).localizedDescription)
        XCTAssertNotNil(store.token)            // loi thuong khong dang xuat
    }
}

final class FormatTests: XCTestCase {
    func testFormatVnd() {
        XCTAssertEqual(formatVnd(0), "0 ₫")
        XCTAssertEqual(formatVnd(999), "999 ₫")
        XCTAssertEqual(formatVnd(125_000), "125.000 ₫")
        XCTAssertEqual(formatVnd(1_234_567), "1.234.567 ₫")
        XCTAssertEqual(formatVnd(-50_000), "-50.000 ₫")
    }

    func testParseIso() {
        XCTAssertEqual(parseIso("2025-08-12T12:30:00Z")?.timeIntervalSince1970, 1_755_001_800)
        XCTAssertNotNil(parseIso("2025-08-12T12:30:00.123Z"))       // co phan giay le
        XCTAssertNil(parseIso("12/08/2025"))
    }

    func testDateFormattersFallBackToRawString() {
        XCTAssertEqual(formatShortDate("khong-phai-ngay"), "khong-phai-ngay")
        XCTAssertEqual(formatDateTime("khong-phai-ngay"), "khong-phai-ngay")
        XCTAssertFalse(formatShortDate("2025-08-12T12:30:00Z").isEmpty)
        XCTAssertTrue(formatDateTime("2025-08-12T12:30:00Z").contains(":"))
    }

    func testCategoryLabels() {
        XCTAssertEqual(categoryEmoji("food"), "🍜")
        XCTAssertEqual(categoryLabel("food"), "Ăn uống")
        XCTAssertEqual(categoryEmoji(""), "❔")
        XCTAssertEqual(categoryLabel(""), "Chưa phân loại")
        XCTAssertEqual(expenseCategories.count, 8)
    }

    func testSettlementLabels() {
        XCTAssertEqual(settlementLabel("p2p"), "Ai nợ ai trả người đó")
        XCTAssertEqual(settlementLabel("la"), "la")             // kind la: hien nguyen ban
        XCTAssertEqual(settlementModes.count, 4)
        XCTAssertEqual(mcpScopeLabels.count, 3)
    }

    func testWeekdayName() {
        XCTAssertEqual(weekdayName(0), "Chủ nhật")
        XCTAssertEqual(weekdayName(6), "Thứ bảy")
        XCTAssertEqual(weekdayName(7), "?")
        XCTAssertEqual(weekdayName(-1), "?")
    }
}

final class DescribeEventTests: XCTestCase {
    private func payload(_ json: String) throws -> ApiGameEventPayload {
        try JSONDecoder().decode(ApiGameEventPayload.self, from: Data(json.utf8))
    }

    func testEveryKind() throws {
        let cases: [(String, String)] = [
            ("{\"kind\":\"game_created\",\"name\":\"Cầu tối\"}", "Tạo cuộc \"Cầu tối\""),
            ("{\"kind\":\"game_renamed\",\"from\":\"A\",\"to\":\"B\"}", "Đổi tên: A → B"),
            ("{\"kind\":\"settlement_changed\",\"mode\":\"p2p\"}", "Chuyển tiền: Ai nợ ai trả người đó"),
            ("{\"kind\":\"settlement_changed\",\"mode\":\"pick\",\"hostName\":\"Huy\"}",
             "Chuyển tiền: Gom về một người tự chọn · Huy"),
            ("{\"kind\":\"participant_added\",\"names\":[\"Huy\",\"Kiệt\"]}", "Thêm người: Huy, Kiệt"),
            ("{\"kind\":\"participant_renamed\",\"from\":\"A\",\"to\":\"B\"}", "Đổi tên người: A → B"),
            ("{\"kind\":\"participant_removed\",\"name\":\"Huy\"}", "Xoá người: Huy"),
            ("{\"kind\":\"expense_added\",\"title\":\"Cầu\",\"amount\":120000,\"payerName\":\"Huy\"}",
             "Thêm chi \"Cầu\" 120.000 ₫ · Huy ứng"),
            ("{\"kind\":\"expense_updated\",\"title\":\"Cầu\",\"amount\":10000}", "Sửa chi \"Cầu\" 10.000 ₫"),
            ("{\"kind\":\"expense_removed\",\"title\":\"Cầu\",\"amount\":10000}", "Xoá chi \"Cầu\" 10.000 ₫"),
            ("{\"kind\":\"expense_restored\",\"title\":\"Cầu\",\"amount\":10000}",
             "Hoàn tác xoá \"Cầu\" 10.000 ₫"),
            ("{\"kind\":\"transfer_added\",\"fromName\":\"A\",\"toName\":\"B\",\"amount\":5000}",
             "Chuyển tiền: A → B 5.000 ₫"),
            ("{\"kind\":\"game_closed\"}", "Đóng cuộc chia"),
            ("{\"kind\":\"game_reopened\"}", "Mở lại cuộc chia"),
            ("{\"kind\":\"kind_moi_tu_server\"}", "kind_moi_tu_server"),
        ]
        for (json, expected) in cases {
            XCTAssertEqual(describeEvent(try payload(json)), expected, json)
        }
    }

    func testMissingFieldsDoNotCrash() throws {
        XCTAssertEqual(describeEvent(try payload("{\"kind\":\"game_created\"}")), "Tạo cuộc \"\"")
        XCTAssertEqual(describeEvent(try payload("{\"kind\":\"expense_added\"}")), "Thêm chi \"\"  ·  ứng")
        XCTAssertEqual(describeEvent(try payload("{\"kind\":\"participant_added\"}")), "Thêm người: ")
    }
}
