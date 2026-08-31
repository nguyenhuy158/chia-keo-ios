import SwiftUI
import UIKit

/// Ban chieu cua src/adapters/browser/summary-image-backgrounds.ts. Mot nen gom
/// cach ve nen va bang mau chu di kem — doi nen ma khong doi mau chu thi nen
/// toi lam chu bien mat.
struct SummaryBackground: Identifiable {
    let id: String
    let label: String
    /// Mau nen, ve theo chieu doc; mot mau = nen tron.
    let colors: [Color]
    /// Hoa van emoji rac mo len nen; [] la khong co.
    let emojis: [String]
    let title: Color
    let body: Color
    let muted: Color
    let accent: Color
    let heading: Color
    let divider: Color
}

private func hex(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 0xFF) / 255,
          green: Double((value >> 8) & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255)
}

private let lightTitle = hex(0x0c0a09)
private let lightBody = hex(0x1c1917)
private let lightMuted = hex(0x645d57)

let summaryBackgrounds: [SummaryBackground] = [
    SummaryBackground(id: "cau-long", label: "Cầu lông mint",
                      colors: [hex(0xf0fdfa), hex(0xccfbf1)], emojis: ["🏸", "✨", "🏸", "🥇"],
                      title: lightTitle, body: lightBody, muted: lightMuted,
                      accent: hex(0x0d9488), heading: hex(0x115e59), divider: hex(0x99f6e4)),
    SummaryBackground(id: "trang", label: "Trắng trơn",
                      colors: [hex(0xffffff)], emojis: [],
                      title: lightTitle, body: lightBody, muted: lightMuted,
                      accent: hex(0x7c3aed), heading: hex(0x6d28d9), divider: hex(0xe7e5e4)),
    SummaryBackground(id: "tim", label: "Tím nhạt",
                      colors: [hex(0xfaf5ff), hex(0xede9fe)], emojis: [],
                      title: lightTitle, body: lightBody, muted: lightMuted,
                      accent: hex(0x7c3aed), heading: hex(0x5b21b6), divider: hex(0xddd6fe)),
    SummaryBackground(id: "kem", label: "Giấy kem",
                      colors: [hex(0xfdfaf3), hex(0xece1c9)], emojis: [],
                      title: lightTitle, body: lightBody, muted: lightMuted,
                      accent: hex(0xb45309), heading: hex(0x92400e), divider: hex(0xe7dcc4)),
    SummaryBackground(id: "bien", label: "Xanh biển",
                      colors: [hex(0xf0f9ff), hex(0xdbeafe)], emojis: [],
                      title: lightTitle, body: lightBody, muted: lightMuted,
                      accent: hex(0x0284c7), heading: hex(0x075985), divider: hex(0xbfdbfe)),
    SummaryBackground(id: "bac-ha", label: "Bạc hà",
                      colors: [hex(0xf0fdf4), hex(0xd1fae5)], emojis: [],
                      title: lightTitle, body: lightBody, muted: lightMuted,
                      accent: hex(0x059669), heading: hex(0x065f46), divider: hex(0xa7f3d0)),
    SummaryBackground(id: "dem", label: "Nền đêm",
                      colors: [hex(0x292524), hex(0x0c0a09)], emojis: [],
                      title: hex(0xfafaf9), body: hex(0xe7e5e4), muted: hex(0xa8a29e),
                      accent: hex(0xa78bfa), heading: hex(0xc4b5fd), divider: hex(0x292524)),
]

/// Id la khong ro (ban cu, key rac) thi ve nen mac dinh.
func summaryBackground(_ id: String?) -> SummaryBackground {
    summaryBackgrounds.first { $0.id == id } ?? summaryBackgrounds[0]
}

/// Nen la so thich cua nguoi dung, khong phai du lieu cuoc chia — luu o may.
enum SummaryBackgroundStore {
    static let key = "chia-keo-summary-image-bg"

    static var id: String {
        get { summaryBackground(UserDefaults.standard.string(forKey: key)).id }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Card

private let cardWidth: CGFloat = 720

struct SummaryCard: View {
    let doc: SummaryDoc
    let background: SummaryBackground

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title).font(.system(size: 34, weight: .bold)).foregroundStyle(background.title)
                Text(doc.subtitle).font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(background.accent)
            }

            ForEach(Array(doc.sections.enumerated()), id: \.offset) { index, section in
                if index > 0 {
                    Rectangle().fill(background.divider).frame(height: 1)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.heading).font(.system(size: 15, weight: .bold))
                        .foregroundStyle(background.heading)
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(size: 17)).foregroundStyle(background.body)
                    }
                }
            }

            if let footer = doc.footer {
                Text(footer).font(.system(size: 14)).foregroundStyle(background.muted)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(width: cardWidth, alignment: .leading)
        .padding(34)
        .background(alignment: .topLeading) {
            ZStack {
                LinearGradient(colors: background.colors.count > 1 ? background.colors
                                                                   : background.colors + background.colors,
                               startPoint: .top, endPoint: .bottom)
                if !background.emojis.isEmpty { EmojiPattern(emojis: background.emojis) }
            }
        }
    }
}

/// Hoa van thua va rat mo, xen le hang cho khong thanh luoi vuong. Vi tri tinh
/// tu chi so hang/cot chu khong random: ve lai phai ra dung mot anh.
private struct EmojiPattern: View {
    let emojis: [String]

    var body: some View {
        Canvas { context, size in
            let spacingX: CGFloat = 116, spacingY: CGFloat = 104
            var row = 0
            var y = spacingY / 2
            while y < size.height {
                var column = 0
                var x = (row.isMultiple(of: 2) ? 0 : spacingX / 2) + spacingX / 2
                while x < size.width {
                    let emoji = emojis[(row + column) % emojis.count]
                    let tilt: CGFloat = (row + column).isMultiple(of: 2) ? 0.18 : -0.18
                    context.drawLayer { layer in
                        layer.opacity = 0.16
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .radians(tilt))
                        layer.draw(Text(emoji).font(.system(size: 30)), at: .zero, anchor: .center)
                    }
                    x += spacingX
                    column += 1
                }
                y += spacingY
                row += 1
            }
        }
    }
}

/// Ve anh PNG cua bang tong ket. nil khi ImageRenderer khong ra duoc anh.
@MainActor
func renderSummaryImage(_ detail: ApiGameDetail,
                        variant: SummaryVariant = .compact,
                        shareUrl: String? = nil,
                        background: SummaryBackground) -> UIImage? {
    let card = SummaryCard(doc: buildSummaryDoc(detail, variant: variant, shareUrl: shareUrl),
                           background: background)
    let renderer = ImageRenderer(content: card)
    renderer.scale = 2                      // du net khi xem tren man hinh retina
    renderer.isOpaque = true
    return renderer.uiImage
}

func summaryImageFileName(_ detail: ApiGameDetail, variant: SummaryVariant) -> String {
    "chia-keo-\(detail.code)\(variant == .detailed ? "-chi-tiet" : "").png"
}
