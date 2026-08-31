import XCTest
@testable import ChiaKeo

/// Chan moi request cua URLSession rieng cua test — khong he goi mang thuc.
final class StubProtocol: URLProtocol {
    /// (status, body) tra ve, hoac loi mang. Dat truoc moi test.
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data("{}".utf8)
    nonisolated(unsafe) static var failure: Error?
    /// Request cuoi cung di qua — de kiem method/header/body.
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        // URLSession doi httpBody thanh stream truoc khi den day.
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            return data
        }

        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ApiClientTests: XCTestCase {
    private var client: ApiClient!

    override func setUp() {
        super.setUp()
        StubProtocol.status = 200
        StubProtocol.body = Data("{}".utf8)
        StubProtocol.failure = nil
        StubProtocol.lastRequest = nil
        StubProtocol.lastBody = nil

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        client = ApiClient(token: "tok", session: URLSession(configuration: config))
    }

    private func expectError(_ body: () async throws -> Void) async -> ApiError? {
        do {
            try await body()
            return nil
        } catch let error as ApiError {
            return error
        } catch {
            XCTFail("loi la: \(error)")
            return nil
        }
    }

    func testGetSetsBearerAndDecodes() async throws {
        StubProtocol.body = Data("{\"stock\":7,\"entries\":[]}".utf8)
        let stock: ApiShuttleStock = try await client.get("/api/shuttles")
        XCTAssertEqual(stock.stock, 7)
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.absoluteString,
                       "https://chiakeo.huyab.click/api/shuttles")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
                       "Bearer tok")
    }

    func testPostWithBodyEncodesJson() async throws {
        StubProtocol.body = Data("{\"stock\":1,\"entries\":[]}".utf8)
        let _: ApiShuttleStock = try await client.post("/api/shuttles",
                                                       body: ShuttleEntryInput(kind: "add", quantity: 3))
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"),
                       "application/json")
        let sent = try JSONSerialization.jsonObject(with: StubProtocol.lastBody ?? Data()) as? [String: Any]
        XCTAssertEqual(sent?["kind"] as? String, "add")
        XCTAssertEqual(sent?["quantity"] as? Int, 3)
    }

    func testPostWithoutBody() async throws {
        StubProtocol.body = Data("{\"token\":\"t\",\"enabled\":true}".utf8)
        let link: ApiShareLinkOnly = try await client.post("/api/games/1/share")
        XCTAssertTrue(link.enabled)
        XCTAssertNil(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"))
    }

    func testPatch() async throws {
        StubProtocol.body = Data("{\"user\":null}".utf8)
        let _: ApiSession = try await client.patch("/api/profile", body: ProfileInput(name: "Huy"))
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "PATCH")
    }

    func testFireIgnoresEmptyBody() async throws {
        StubProtocol.body = Data()          // body rong van phai coi la thanh cong
        try await client.fire("/api/games/1", method: "DELETE")
        XCTAssertEqual(StubProtocol.lastRequest?.httpMethod, "DELETE")
    }

    func testUnauthorized() async {
        StubProtocol.status = 401
        let error = await expectError { try await self.client.fire("/api/games/1", method: "POST") }
        XCTAssertEqual(error?.errorDescription, ApiError.unauthorized.errorDescription)
    }

    func testNonSuccessStatus() async {
        StubProtocol.status = 500
        let error = await expectError { try await self.client.fire("/api/games/1", method: "POST") }
        XCTAssertEqual(error?.errorDescription, "Máy chủ trả lỗi 500")
    }

    func testTransportFailure() async {
        StubProtocol.failure = URLError(.notConnectedToInternet)
        let error = await expectError { try await self.client.fire("/api/games", method: "GET") }
        XCTAssertNotNil(error?.errorDescription)
    }

    func testDecodeFailureIsReported() async {
        StubProtocol.body = Data("[]".utf8)      // array trong khi cho object
        let error = await expectError {
            let _: ApiShuttleStock = try await self.client.get("/api/shuttles")
        }
        XCTAssertTrue(error?.errorDescription?.contains("đọc được") ?? false, "\(error as Any)")
    }
}
