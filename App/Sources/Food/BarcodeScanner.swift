import StezuCore
import SwiftUI
import Vision
import VisionKit

/// Where Barcode mode gets codes (S-016): VisionKit's DataScanner on the phone, or one synthetic
/// code in `-uitest`, so the simulator needs no camera.
enum BarcodeSource: Sendable {
  case camera
  /// Delivered once, 8 seconds after Barcode mode opens.
  case fixture(String)
}

/// Barcode mode over the camera, between a scanned code and the item list.
enum BarcodeState: Equatable {
  case scanning, lookingUp, notFound, failed

  var message: String {
    switch self {
    case .scanning: "Point the camera at a barcode"
    case .lookingUp: "Looking up..."
    case .notFound: "Not found"
    case .failed: "Could not look up the code"
    }
  }
}

/// The line under the frame in Barcode mode; a code with no product offers search instead.
struct BarcodeStatusView: View {
  let state: BarcodeState
  let searchInstead: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Color.white, lineWidth: 3)
        .frame(width: 260, height: 140)
      VStack(spacing: 10) {
        Text(state.message).font(.system(size: Theme.subtitleSize, weight: .semibold))
          .accessibilityIdentifier("food.barcode.status")
        if state == .notFound || state == .failed {
          Button("Search instead", action: searchInstead)
            .font(.system(size: Theme.labelSize, weight: .semibold))
            .foregroundStyle(Theme.invertedText).padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Theme.invertedCard))
            .accessibilityIdentifier("food.barcode.search")
        }
      }
      .foregroundStyle(Theme.text).padding(14)
      .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.card))
    }
  }
}

/// VisionKit's live scanner for package codes (EAN-8, EAN-13, which includes UPC-A). Each newly
/// recognized code is passed on once; a code that stays in view is not passed again.
struct BarcodeScannerView: UIViewControllerRepresentable {
  let onCode: (String) -> Void

  @MainActor static var available: Bool {
    DataScannerViewController.isSupported && DataScannerViewController.isAvailable
  }

  func makeUIViewController(context: Context) -> DataScannerViewController {
    let scanner = DataScannerViewController(
      recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13])], qualityLevel: .balanced,
      isHighlightingEnabled: true)
    scanner.delegate = context.coordinator
    return scanner
  }

  func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
    context.coordinator.onCode = onCode
    if !scanner.isScanning { try? scanner.startScanning() }
  }

  static func dismantleUIViewController(
    _ scanner: DataScannerViewController, coordinator: Coordinator
  ) {
    scanner.stopScanning()
  }

  func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

  @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    var onCode: (String) -> Void

    init(onCode: @escaping (String) -> Void) {
      self.onCode = onCode
    }

    func dataScanner(
      _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
      allItems: [RecognizedItem]
    ) {
      for case .barcode(let code) in addedItems {
        if let payload = code.payloadStringValue { onCode(payload) }
      }
    }
  }
}
