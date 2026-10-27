import SwiftUI
import UIKit

/// The Ingest design system's tokens (design/system/tokens.json, version 2), under their token
/// names. This is the only file that defines colours, type sizes, spacing, radii and sizes;
/// scripts/gate-linux.sh G7 fails on colour or font literals anywhere else and checks these
/// values against tokens.json. Compiled into the app and the RestActivity extension.
enum Theme {
  // MARK: Colour. Each one resolves Light or Dark from the view's trait collection.

  static let ground = color(0xE6E6E6, dark: 0x111111)
  static let surface = color(0xEFEFEF, dark: 0x1A1A1A)
  static let surfaceRaised = color(0xFFFFFF, dark: 0x262626)
  static let edge = color(0xFFFFFF, dark: 0x2C2C2C)
  static let ink = color(0x0B0B0B, dark: 0xF2F2F2)
  static let muted = color(0x5E5E5E, dark: 0xA3A3A3)
  static let invert = color(0x0B0B0B, dark: 0xF2F2F2)
  static let onInvert = color(0xFFFFFF, dark: 0x0B0B0B)
  static let onInvertMuted = color(0x9C9C9C, dark: 0x5E5E5E)
  static let track = color(0xD4D4D4, dark: 0x2E2E2E)
  static let focus = color(0x0B0B0B, dark: 0xF2F2F2)
  static let camera = color(0x000000, dark: 0x000000)
  static let onCamera = color(0xFFFFFF, dark: 0xFFFFFF)
  static let cameraScrim = color(0x000000, dark: 0x000000, alpha: 0.55, darkAlpha: 0.55)
  static let dataEnergy = color(0xA04B17, dark: 0xE8954F)
  static let dataEnergyBand = color(0xA04B17, dark: 0xE8954F, alpha: 0.18, darkAlpha: 0.22)
  static let dataProtein = color(0x0E6B66, dark: 0x5CC3BA)
  static let dataProteinBand = color(0x0E6B66, dark: 0x5CC3BA, alpha: 0.18, darkAlpha: 0.22)
  static let dataHeart = color(0xB3363A, dark: 0xF07A7A)
  static let dataSample = color(0x7A7A7A, dark: 0x8C8C8C)
  static let dataTrend = ink
  static let sleepDeep = color(0x1B2F5C, dark: 0x4A6FB8)
  static let sleepCore = color(0x3A64A8, dark: 0x7BA3E0)
  static let sleepRem = color(0x6F95D1, dark: 0xB5D0F5)
  static let sleepAwake = color(0xB8650A, dark: 0xE3A33B)
  static let signalError = color(0xA6261E, dark: 0xFF8A80)
  static let signalPending = color(0x8A5A00, dark: 0xE8B44C)

  // MARK: Spacing, radius, size (points).

  static let space2xs: CGFloat = 2
  static let spaceXs: CGFloat = 4
  static let spaceSm: CGFloat = 8
  static let spaceMd: CGFloat = 12
  static let spaceLg: CGFloat = 16
  static let spaceCard: CGFloat = 18
  static let spaceXl: CGFloat = 24
  static let space2xl: CGFloat = 32

  static let radiusCard: CGFloat = 18
  static let radiusInner: CGFloat = 12
  static let radiusChip: CGFloat = 8
  static let radiusPill: CGFloat = 999

  static let sizeTarget: CGFloat = 44
  static let sizeControl: CGFloat = 48
  static let sizeNav: CGFloat = 58
  static let sizeShutter: CGFloat = 74
  static let sizeSpark: CGFloat = 28
  static let sizeChart: CGFloat = 140

  // MARK: Type. SF Pro through the system font; set a style with `.textStyle(_:)`.

  enum TextStyle: CaseIterable, Sendable {
    case hero, big, stat, title1, title2, headline, value, body, subtitle, label, axis

    /// The size at the default Dynamic Type setting.
    var size: CGFloat {
      switch self {
      case .hero: 76
      case .big: 42
      case .stat, .title2: 28
      case .title1: 34
      case .headline, .value, .body: 17
      case .subtitle: 15
      case .label: 12
      case .axis: 11
      }
    }

    /// The iOS text style the size scales with.
    var relativeTo: Font.TextStyle {
      switch self {
      case .hero, .big, .title1: .largeTitle
      case .stat, .title2: .title
      case .headline: .headline
      case .value, .body: .body
      case .subtitle: .subheadline
      case .label: .caption
      case .axis: .caption2
      }
    }

    var weight: Font.Weight {
      switch self {
      case .hero, .big, .stat, .value, .axis: .medium
      case .title1, .title2, .headline: .semibold
      case .body, .subtitle, .label: .regular
      }
    }

    /// Letter spacing in points.
    var tracking: CGFloat {
      switch self {
      case .hero: -1.5
      case .big: -1
      case .stat: -0.5
      case .label: 0.1
      default: 0
      }
    }

    /// Number styles use tabular digits, so values do not shift as they change.
    var tabularDigits: Bool {
      switch self {
      case .hero, .big, .stat, .value, .axis: true
      default: false
      }
    }
  }

  /// A colour from 0xRRGGBB values for Light and Dark, resolved when the view draws.
  private static func color(
    _ light: UInt32, dark: UInt32, alpha: CGFloat = 1, darkAlpha: CGFloat = 1
  ) -> Color {
    Color(
      uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
          ? rgb(dark, alpha: darkAlpha) : rgb(light, alpha: alpha)
      })
  }

  private static func rgb(_ hex: UInt32, alpha: CGFloat) -> UIColor {
    UIColor(
      red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
  }
}

extension View {
  /// One of the design system's type styles: the size follows Dynamic Type through the style's
  /// iOS text style, numbers get tabular digits, and the style's tracking comes with it.
  /// `weight` overrides the style's own weight.
  func textStyle(_ style: Theme.TextStyle, weight: Font.Weight? = nil) -> some View {
    modifier(ThemeTextStyle(style: style, weight: weight))
  }
}

private struct ThemeTextStyle: ViewModifier {
  let style: Theme.TextStyle
  let weight: Font.Weight?
  @ScaledMetric private var size: CGFloat

  init(style: Theme.TextStyle, weight: Font.Weight?) {
    self.style = style
    self.weight = weight
    _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
  }

  private var scaledFont: Font {
    let font = Font.system(size: size, weight: weight ?? style.weight)
    return style.tabularDigits ? font.monospacedDigit() : font
  }

  @ViewBuilder
  func body(content: Content) -> some View {
    if style.tracking == 0 {
      content.font(scaledFont)
    } else {
      content.font(scaledFont).tracking(style.tracking)
    }
  }
}
