import Foundation
import UIKit

/// Where meal photos come from. The live camera arrives with the Food stories; `-uitest` launches
/// use FixturePhotoSource, so the simulator needs no camera.
protocol PhotoSource: Sendable {
  /// Takes one photo and returns JPEG data. Callers save it locally before any network call.
  func capturePhoto() async throws -> Data
  /// Asks for camera access when iOS has not asked yet; false when it is denied or restricted.
  func authorize() async -> Bool
}

extension PhotoSource {
  /// Sources without a camera need no permission.
  func authorize() async -> Bool { true }
}

enum PhotoSourceError: Error, Equatable {
  case cameraUnavailable
}

/// The live app's source until the camera story replaces it.
struct NoCameraPhotoSource: PhotoSource {
  func capturePhoto() async throws -> Data {
    throw PhotoSourceError.cameraUnavailable
  }
}

/// A synthetic plate drawn in code: no camera in the simulator and no real photo in the repo.
struct FixturePhotoSource: PhotoSource {
  func capturePhoto() async throws -> Data {
    await Self.plateJPEG()
  }

  @MainActor
  static func plateJPEG(side: CGFloat = 600) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let bounds = CGRect(x: 0, y: 0, width: side, height: side)
    let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
    return renderer.jpegData(withCompressionQuality: 0.8) { context in
      UIColor(white: 0.85, alpha: 1).setFill()
      context.fill(bounds)
      UIColor.white.setFill()
      UIBezierPath(ovalIn: bounds.insetBy(dx: side * 0.08, dy: side * 0.08)).fill()
      UIColor(red: 0.85, green: 0.65, blue: 0.35, alpha: 1).setFill()
      UIBezierPath(
        ovalIn: CGRect(x: side * 0.25, y: side * 0.3, width: side * 0.3, height: side * 0.25)
      )
      .fill()
      UIColor(red: 0.35, green: 0.6, blue: 0.3, alpha: 1).setFill()
      UIBezierPath(
        ovalIn: CGRect(x: side * 0.5, y: side * 0.45, width: side * 0.25, height: side * 0.22)
      )
      .fill()
    }
  }
}
