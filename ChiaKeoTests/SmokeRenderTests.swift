import SwiftUI
import XCTest
@testable import ChiaKeo

/**
 * Tra loi thay server that cho MOI request cua URLSession.shared, chon body
 * theo duong dan. Dang ky toan cuc nen cac view (dung auth.client -> shared)
 * chay duoc trong test ma khong cham mang.
 */
final class RouterProtocol: URLProtocol {
    /// normal = du lieu day; empty = list rong / thieu du lieu; error = 500.
    enum Mode { case normal, empty, error }
    nonisolated(unsafe) static var mode = Mode.normal
    nonisolated(unsafe) static var seenPaths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "chiakeo.huyab.click"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func body(for path: String) -> String {
        let game = """
        {"id":"g1","code":"ABC","name":"Cầu tối","createdAt":"2025-08-12T12:00:00Z",
         "participantCount":2,"expenseCount":1,"closedAt":null,"closeMode":"manual","isOwner":true}
        """
        switch path {
        case "/api/games", "/api/games/closed":
            return "[\(game)]"
        case "/api/games/trash":
            return "[{\"id\":\"g2\",\"code\":\"XYZ\",\"name\":\"Cũ\",\"deletedAt\":\"2025-08-12T12:00:00Z\"}]"
        case "/api/cross-balances":
            return """
            {"totalExpense":300000,"omittedGameCount":1,
             "people":[{"name":"Huy","paid":300000,"owed":100000,"net":200000,
                        "games":[{"code":"ABC","name":"Cầu","balance":200000}]}],
             "settlements":[{"from":"Kiệt","to":"Huy","amount":100000}],
             "namesInOneGameOnly":["Nam"]}
            """
        case "/api/contacts":
            return """
            {"contacts":[{"key":"huy","id":"c1","name":"Huy","bankId":"TCB","accountNo":"1",
                          "accountName":"HUY","gameCount":3,"source":"book"},
                         {"key":"kiet","id":null,"name":"Kiệt","bankId":"","accountNo":"",
                          "accountName":"","gameCount":7,"source":"history"}]}
            """
        case "/api/shuttles":
            return """
            {"stock":12,"entries":[{"id":"s1","kind":"add","delta":6,"stockAfter":12,
                                    "note":"mua","createdAt":"2025-08-12T12:00:00Z"}]}
            """
        case "/api/fun-stats":
            return """
            {"gameCount":5,"totalExpense":900000,
             "topPayer":{"name":"Huy","totalPaid":500000,"gameCount":5},
             "mostActive":{"name":"Kiệt","totalPaid":100000,"gameCount":5},
             "biggestExpense":{"title":"Cầu","amount":200000,"gameName":"Cầu tối"},
             "biggestGame":{"name":"Cầu tối","participantCount":8},
             "favoriteWeekday":3,"omittedGameCount":1}
            """
        case "/api/session":
            return "{\"user\":{\"id\":\"u1\",\"name\":\"Huy\",\"image\":null}}"
        case "/api/mcp-tokens":
            return """
            [{"id":"m1","name":"Claude","tokenPrefix":"ck_ab","scopes":["games:read"],
              "createdAt":"2025-08-12T12:00:00Z","expiresAt":null,"active":true}]
            """
        default:
            break
        }
        if path.hasSuffix("/photos") {
            return """
            [{"id":"ph1","caption":"hoá đơn","thumbData":"","createdAt":"2025-08-12T12:00:00Z"}]
            """
        }
        if path.hasSuffix("/events") {
            return """
            {"events":[{"id":"ev1","createdAt":"2025-08-12T12:00:00Z","undoneAt":null,
                        "payload":{"kind":"expense_removed","title":"Cầu","amount":10000}},
                       {"id":"ev2","createdAt":"2025-08-12T12:00:00Z","undoneAt":null,
                        "payload":{"kind":"game_created","name":"Cầu tối"}}]}
            """
        }
        if path.hasSuffix("/share/candidates") { return "[]" }
        if path.hasPrefix("/api/games/") {
            return """
            {"id":"g1","code":"ABC","name":"Cầu tối","settlementMode":"p2p","settlementHostId":"",
             "closedAt":null,"closeMode":"manual",
             "participants":[{"id":"p1","name":"Huy","bankId":"TCB","accountNo":"1","accountName":"HUY"},
                             {"id":"p2","name":"Kiệt","bankId":"","accountNo":"","accountName":""}],
             "expenses":[{"id":"e1","kind":"expense","category":"food","title":"Cầu","amount":120000,
                          "note":"","payerParticipantId":"p1","splitMode":"equal",
                          "splitParticipantIds":["p1","p2"],"createdAt":"2025-08-12T12:00:00Z"},
                         {"id":"e2","kind":"income","category":"","title":"Hoàn","amount":20000,
                          "note":"","payerParticipantId":"p2","splitMode":"equal",
                          "splitParticipantIds":["p1"],"createdAt":"2025-08-12T12:00:00Z"}],
             "summary":{"totalExpense":120000,
                        "balances":[{"participantId":"p1","paid":120000,"owed":60000,"balance":60000},
                                    {"participantId":"p2","paid":0,"owed":60000,"balance":-60000}],
                        "settlements":[{"fromParticipantId":"p2","toParticipantId":"p1","amount":60000}]},
             "shareLink":{"token":"t","enabled":true},"isOwner":true,
             "collaborators":[{"userId":"u2","name":"Ai do","email":"a@b.c"}]}
            """
        }
        return "{}"
    }

    /// Cuoc da dong, khong nguoi, khong chi, khong link chia se — nhanh else
    /// cua moi man hinh.
    private static func emptyBody(for path: String) -> String {
        switch path {
        case "/api/games", "/api/games/closed", "/api/games/trash", "/api/mcp-tokens":
            return "[]"
        case "/api/contacts": return "{\"contacts\":[]}"
        case "/api/shuttles": return "{\"stock\":0,\"entries\":[]}"
        case "/api/cross-balances":
            return """
            {"totalExpense":0,"omittedGameCount":0,"people":[],"settlements":[],
             "namesInOneGameOnly":[]}
            """
        case "/api/fun-stats":
            return """
            {"gameCount":0,"totalExpense":0,"topPayer":null,"mostActive":null,
             "biggestExpense":null,"biggestGame":null,"favoriteWeekday":null,"omittedGameCount":0}
            """
        case "/api/session": return "{\"user\":null}"
        default: break
        }
        if path.hasSuffix("/photos") { return "[]" }
        if path.hasSuffix("/events") { return "{\"events\":[]}" }
        if path.hasSuffix("/share/candidates") { return "[]" }
        if path.hasPrefix("/api/games/") {
            return """
            {"id":"g1","code":"ABC","name":"Cầu","settlementMode":"off","settlementHostId":"",
             "closedAt":"2025-08-13T00:00:00Z","closeMode":"manual","participants":[],
             "expenses":[],"summary":{"totalExpense":0,"balances":[],"settlements":[]},
             "shareLink":null,"isOwner":false,"collaborators":[]}
            """
        }
        return "{}"
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.seenPaths.append(path)
        let code = Self.mode == .error ? 500 : 200
        let body: String
        switch Self.mode {
        case .normal: body = Self.body(for: path)
        case .empty: body = Self.emptyBody(for: path)
        case .error: body = "{}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class SmokeRenderTests: XCTestCase {
    private var window: UIWindow!
    private var auth: AuthStore!

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(RouterProtocol.self)
        RouterProtocol.seenPaths = []
        RouterProtocol.mode = .normal
        Keychain.write(fakeJwt(exp: Date().addingTimeInterval(3600).timeIntervalSince1970))
        auth = AuthStore()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 414, height: 896))
    }

    override func tearDown() {
        URLProtocol.unregisterClass(RouterProtocol.self)
        Keychain.clear()
        SsoCookie.remove()
        window = nil
        super.tearDown()
    }

    /// Dung view len that su: `body` chay, `.task` chay, decode chay. Mot man
    /// hinh vo (crash hoac decode sai kieu) la test do ngay.
    private func render(_ view: some View, seconds: TimeInterval = 0.4) async {
        let host = UIHostingController(rootView: view.environmentObject(auth))
        window.rootViewController = host
        window.isHidden = false
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    func testRootTabs() async {
        await render(RootTabs(), seconds: 0.8)
        XCTAssertTrue(RouterProtocol.seenPaths.contains("/api/games"))
    }

    func testLoginView() async {
        auth.signOut(notice: "Phiên đã hết hạn, đăng nhập lại nhé.")
        await render(LoginView(), seconds: 0.2)
    }

    func testEveryRoute() async {
        for route in Self.allRoutes {
            await render(NavigationStack { route.view })
        }
        XCTAssertTrue(RouterProtocol.seenPaths.contains("/api/contacts"))
        XCTAssertTrue(RouterProtocol.seenPaths.contains("/api/games/trash"))
        XCTAssertTrue(RouterProtocol.seenPaths.contains("/api/mcp-tokens"))
    }

    func testStandaloneTabs() async {
        await render(NavigationStack { ShuttlesView() })
        await render(NavigationStack { FunStatsView() })
        await render(NavigationStack { SettingsView() })
        XCTAssertTrue(RouterProtocol.seenPaths.contains("/api/fun-stats"))
        XCTAssertTrue(RouterProtocol.seenPaths.contains("/api/session"))
    }

    /// Cuoc da dong / list rong: nhanh else cua tung man hinh.
    func testEveryRouteEmptyState() async {
        RouterProtocol.mode = .empty
        await renderAllRoutes()
    }

    /// Server 500: moi man hinh phai hien loi chu khong vo.
    func testEveryRouteErrorState() async {
        RouterProtocol.mode = .error
        await renderAllRoutes()
    }

    private func renderAllRoutes() async {
        for route in Self.allRoutes {
            await render(NavigationStack { route.view }, seconds: 0.25)
        }
        await render(NavigationStack { ShuttlesView() }, seconds: 0.25)
        await render(NavigationStack { FunStatsView() }, seconds: 0.25)
        await render(NavigationStack { SettingsView() }, seconds: 0.25)
    }

    private static let allRoutes: [Route] = [
        .game("g1"), .crossBalances, .contacts, .closedGames, .trash,
        .gamePhotos("g1"), .gameHistory("g1"), .gameOptions("g1"), .mcpTokens,
    ]

    /// Chon nguoi quen: nguoi da co trong cuoc chia bi mo di (doi chieu ten da
    /// chuan hoa), nguoi con lai them duoc bang /participants/batch.
    func testContactPicker() async {
        let json = "[{\"id\":\"p1\",\"name\":\" Huy \",\"bankId\":\"\",\"accountNo\":\"\",\"accountName\":\"\"}]"
        let people = try! JSONDecoder().decode([ApiParticipant].self, from: Data(json.utf8))
        await render(ContactPickerView(gameId: "g1", participants: people, done: {}), seconds: 0.4)
        XCTAssertTrue(RouterProtocol.seenPaths.contains("/api/contacts"))
    }

    func testRows() async {
        let game = try! JSONDecoder().decode(ApiGame.self, from: Data("""
        {"id":"g1","code":"ABC","name":"Cầu tối","createdAt":"2025-08-12T12:00:00Z",
         "participantCount":2,"expenseCount":1,"closedAt":"2025-08-13T00:00:00Z",
         "closeMode":"auto","isOwner":false}
        """.utf8))
        await render(List { GameRow(game: game); TransferRow(from: "A", to: "B", amount: 1000) },
                     seconds: 0.1)
    }

    func testFormsAndSheets() async {
        let detail: ApiGameDetail = try! JSONDecoder().decode(ApiGameDetail.self, from: Data("""
        {"id":"g1","code":"ABC","name":"Cầu","settlementMode":"p2p","settlementHostId":"",
         "closedAt":null,"closeMode":"manual",
         "participants":[{"id":"p1","name":"Huy","bankId":"TCB","accountNo":"1","accountName":"HUY"}],
         "expenses":[{"id":"e1","kind":"expense","category":"food","title":"Cầu","amount":120000,
                      "note":"ghi chú","payerParticipantId":"p1","splitMode":"amount",
                      "splitParticipantIds":["p1"],"splits":[{"participantId":"p1","amount":120000}],
                      "createdAt":"2025-08-12T12:00:00Z"}],
         "summary":{"totalExpense":120000,
                    "balances":[{"participantId":"p1","paid":120000,"owed":120000,"balance":0}],
                    "settlements":[]},
         "shareLink":null,"isOwner":true,"collaborators":[]}
        """.utf8))
        await render(NavigationStack { AddExpenseView(game: detail, onSaved: {}) }, seconds: 0.2)
        // Che do sua: dien san, va canh bao khoan dang chia tuy chinh.
        await render(NavigationStack {
            AddExpenseView(game: detail, expense: detail.expenses[0], onSaved: {})
        }, seconds: 0.3)
        await render(NavigationStack {
            PersonFormView(gameId: "g1", participant: detail.participants[0], done: {})
        }, seconds: 0.2)
        await render(NavigationStack { PersonFormView(gameId: "g1", done: {}) }, seconds: 0.2)
    }
}
