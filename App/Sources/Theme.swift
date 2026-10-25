import SwiftUI

/// Design tokens from DESIGN.md. This is the only place they are defined.
enum Theme {
  static let background = Color(hex: 0xE6E6E6)
  static let card = Color(hex: 0xEFEFEF)
  static let cardBorder = Color.white
  static let invertedCard = Color(hex: 0x0B0B0B)
  static let invertedText = Color.white
  static let label = Color(hex: 0x8A8A8A)
  static let text = Color(hex: 0x0B0B0B)

  static let cardRadius: CGFloat = 18
  static let labelSize: CGFloat = 11.5
  static let subtitleSize: CGFloat = 15
  static let bigNumberSize: CGFloat = 42
  static let bigNumberTracking: CGFloat = -1
  static let heroNumberSize: CGFloat = 76
  static let navCircleSize: CGFloat = 58
}

extension Color {
  /// Creates an sRGB color from a 0xRRGGBB value.
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: 1
    )
  }
}
