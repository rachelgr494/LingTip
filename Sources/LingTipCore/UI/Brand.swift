import SwiftUI

/// Palette sampled from `LingTip Translation Logo.png` (see Scripts/make_icons.swift).
enum Brand {
    static let navy = Color(hex: 0x050E22)
    static let gold = Color(hex: 0xFEC321)
    static let orange = Color(hex: 0xFFAC18)
    static let pink = Color(hex: 0xFD456B)
    static let coral = Color(hex: 0xFE7D78)
    static let cream = Color(hex: 0xFCF8F2)

    /// The bubble's gold → orange → pink sweep.
    static let gradient = LinearGradient(
        colors: [gold, orange, pink],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
