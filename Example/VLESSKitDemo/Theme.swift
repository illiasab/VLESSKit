import SwiftUI

enum Palette {
    static let screen = Color(hex: 0x0B0D12)
    static let card = Color(hex: 0x151922)
    static let card2 = Color(hex: 0x1B2030)
    static let ringCore = Color(hex: 0x141925)
    static let line = Color(hex: 0x252B3B)
    static let text = Color(hex: 0xEEF1F7)
    static let muted = Color(hex: 0x8A93A8)
    static let accent = Color(hex: 0x5CF2B0)
    static let accentDim = Color(hex: 0x5CF2B0, opacity: 0.14)
    static let warn = Color(hex: 0xFFB547)
    static let off = Color(hex: 0xFF6B6B)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
