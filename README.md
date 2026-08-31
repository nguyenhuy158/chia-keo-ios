# Chia Keo iOS

Client native cho [chia-keo](../chia-keo) trên iPhone. Không phải cả web app thu
nhỏ — chỉ ba việc mà điện thoại làm tốt hơn laptop: xem cuộc chia, **chụp hoá đơn
thêm khoản chi**, và xem ai trả ai.

Tạo cuộc chia, collaborator, album ảnh, settings → vẫn làm trên web.

## Đăng nhập

Dùng chung SSO `auth.huyab.click` với web, **cùng một account, cùng `userId`** —
không có tài khoản riêng cho app.

SSO chỉ nhận `redirect_uri` là https trong `huyab.click`, không nhận custom
scheme, nên `ASWebAuthenticationSession` không dùng được. Thay vào đó app mở
`WKWebView` tới `/login?redirect_uri=https://chiakeo.huyab.click/`; khi webview
về tới domain đó, `WKHTTPCookieStore` đọc cookie `huyab_sso` — native API này
đọc được cả HttpOnly, đúng chỗ JavaScript không với tới. JWT vào Keychain, từ đó
gọi API bằng `Authorization: Bearer`.

App **không** verify chữ ký JWT (không có public key, và không cần — worker
verify mọi request). Nó chỉ đọc `exp` để biết khi nào khỏi gọi API.

Cần một thay đổi nhỏ bên worker: `readSsoToken` trong `chia-keo/worker/src/sso.ts`
đọc thêm `Authorization: Bearer` ngoài cookie. Không nới lỏng bảo mật — token vẫn
qua `verifySsoToken` y như cũ.

⚠️ `SESSION_TTL_SECONDS` của repo `sso` đang là **86400 (1 ngày)**, nghĩa là phải
đăng nhập lại mỗi ngày. SSO không có refresh token nên app không lách được. Nâng
lên `2592000` (30 ngày) trong `sso/wrangler.jsonc` nếu thấy phiền.

## Build

    open ChiaKeo.xcodeproj                                  # simulator: Cmd-R
    xcodebuild -scheme ChiaKeo -sdk iphonesimulator build

## Cài lên máy thật

Giống [Koma](../../macos-app/ios-app): Xcode 15.4 không install được lên iOS 26.3
nên Sideloadly làm việc đó với Apple ID free.

    ./make-ipa.sh          # -> build/ChiaKeo.ipa

Kéo .ipa vào Sideloadly. Chữ ký hết hạn sau 7 ngày — re-sign lại. Keychain còn
nguyên qua re-sign nên không phải đăng nhập lại.

## Không có gì ngoài SwiftUI

Zero dependency: không SPM, không CocoaPods, không SDK Google. Logic chia tiền
nằm hết ở worker, app chỉ là client HTTP.
