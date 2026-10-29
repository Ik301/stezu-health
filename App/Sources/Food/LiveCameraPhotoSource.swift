import AVFoundation
import SwiftUI
import UIKit

/// The phone's back camera, run on a private queue. The input is added on the first `start()`
/// after access is granted; `capturePhoto()` returns JPEG data.
final class LiveCameraPhotoSource: PhotoSource, @unchecked Sendable {
  let session = AVCaptureSession()
  /// The one preview layer, bound to the session at launch, before it ever runs. Every Food
  /// screen shows this layer rather than binding a new one: a session feeds one preview layer,
  /// so a new layer bound while the last screen's was still alive stayed black, and binding on
  /// the main thread while the camera queue started or stopped the session could stall taps.
  let previewLayer = AVCaptureVideoPreviewLayer()
  private let output = AVCapturePhotoOutput()
  private let queue = DispatchQueue(label: "stezu.camera")

  init() {
    previewLayer.session = session
    previewLayer.videoGravity = .resizeAspectFill
  }

  func authorize() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return true
    case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
    default: return false
    }
  }

  func start() {
    queue.async { [self] in
      if session.inputs.isEmpty,
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
        let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input),
        session.canAddOutput(output)
      {
        session.addInput(input)
        session.addOutput(output)
      }
      if !session.isRunning { session.startRunning() }
    }
  }

  func stop() { queue.async { [self] in self.session.stopRunning() } }

  func capturePhoto() async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        guard session.isRunning, !session.inputs.isEmpty else {
          return continuation.resume(throwing: PhotoSourceError.cameraUnavailable)
        }
        let delegate = PhotoDelegate()
        delegate.done = { data, error in
          _ = delegate  // the capture holds the delegate weakly; this keeps it until the photo
          guard let data else {
            return continuation.resume(throwing: error ?? PhotoSourceError.cameraUnavailable)
          }
          continuation.resume(returning: data)
        }
        let format = [AVVideoCodecKey: AVVideoCodecType.jpeg]
        output.capturePhoto(with: AVCapturePhotoSettings(format: format), delegate: delegate)
      }
    }
  }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
  /// Called once; clearing it releases the delegate.
  var done: ((Data?, Error?) -> Void)?

  func photoOutput(
    _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
  ) {
    done?(photo.fileDataRepresentation(), error)
    done = nil
  }
}

/// The live camera image, filling its frame: the source's one preview layer, moved into this
/// view (adding a layer takes it out of the last screen's view).
struct CameraPreview: UIViewRepresentable {
  let preview: AVCaptureVideoPreviewLayer

  func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView()
    view.layer.addSublayer(preview)
    view.preview = preview
    return view
  }

  func updateUIView(_ uiView: PreviewView, context: Context) {}

  final class PreviewView: UIView {
    var preview: AVCaptureVideoPreviewLayer?

    override func layoutSubviews() {
      super.layoutSubviews()
      guard let preview, preview.superlayer === layer else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      preview.frame = bounds
      CATransaction.commit()
    }
  }
}
