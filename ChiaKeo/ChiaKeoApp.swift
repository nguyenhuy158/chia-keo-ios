import SwiftUI

@main
struct ChiaKeoApp: App {
    @StateObject private var auth = AuthStore()

    init() {
        #if DEBUG
        selfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            // Mot cong duy nhat: co token thi vao app, khong thi man dang nhap.
            // Moi view goi auth.signOut() khi gap 401 nen het han la tu quay ve day.
            if auth.token == nil {
                LoginView().environmentObject(auth)
            } else {
                RootTabs().environmentObject(auth)
            }
        }
    }
}

#if DEBUG
/// Kiem tra nhanh hai cho de sai am tham: doc `exp` cua JWT va dinh dang tien.
/// Chay luc khoi dong ban Debug — sai la crash ngay tren simulator.
private func selfCheck() {
    // {"exp":2000000000} base64url, khong padding — dung dang SSO tra ve.
    let payload = "eyJleHAiOjIwMDAwMDAwMDB9"
    let future = "header.\(payload).sig"
    assert(SsoToken.expiry(future) == Date(timeIntervalSince1970: 2_000_000_000))
    assert(SsoToken.isUsable(future))

    // {"exp":1000000000} — nam 2001, chac chan het han.
    assert(!SsoToken.isUsable("header.eyJleHAiOjEwMDAwMDAwMDB9.sig"))
    assert(!SsoToken.isUsable("khong-phai-jwt"))
    assert(SsoToken.expiry("a.b.c") == nil)

    assert(formatVnd(125_000) == "125.000 ₫")
    assert(formatVnd(0) == "0 ₫")
    assert(formatVnd(-50_000) == "-50.000 ₫")
}
#endif
