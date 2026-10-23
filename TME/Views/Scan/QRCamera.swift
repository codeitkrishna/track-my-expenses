import AVFoundation
import CoreImage
import SwiftUI
import UIKit
import Vision

/// The back camera, watching for QR codes.
@MainActor
@Observable
final class QRCamera: NSObject {
    enum State: Equatable {
        case starting
        case running
        /// Camera access was turned off for TME.
        case denied
        /// No camera to use, as in the Simulator.
        case unavailable
    }

    private(set) var state = State.starting
    private(set) var hasTorch = false
    private(set) var torchOn = false
    /// Every code the camera reads, many times a second while it's in view.
    @ObservationIgnored var onCode: ((String) -> Void)?
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private let queue = DispatchQueue(label: "tme.camera")

    func start() async {
        // UI tests get no permission prompts, and the Simulator has no camera.
        if LaunchOptions.isUITesting {
            state = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }
        guard configure() else {
            state = .unavailable
            return
        }
        let box = SessionBox(session: session)
        // startRunning blocks until the camera is up, so not on the main thread.
        await withCheckedContinuation { done in
            queue.async {
                box.session.startRunning()
                done.resume()
            }
        }
        state = .running
    }

    func stop() {
        if torchOn { toggleTorch() }
        let box = SessionBox(session: session)
        queue.async { box.session.stopRunning() }
    }

    func toggleTorch() {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = torchOn ? .off : .on
        device.unlockForConfiguration()
        torchOn.toggle()
    }

    private func configure() -> Bool {
        if !session.inputs.isEmpty { return true }
        // The multi-camera devices switch to the ultra-wide by themselves
        // when a code is held too close for the main camera to focus.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        guard let device = discovery.devices.first, let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let output = AVCaptureMetadataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        if (try? device.lockForConfiguration()) != nil {
            // Start at the 1× everyone knows, not the ultra-wide's 0.5×.
            if let wide = device.virtualDeviceSwitchOverVideoZoomFactors.first {
                device.videoZoomFactor = CGFloat(truncating: wide)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            device.unlockForConfiguration()
        }
        self.device = device
        hasTorch = device.hasTorch
        return true
    }
}

extension QRCamera: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let codes = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        // Delivered on the main queue, as set up in `configure`.
        MainActor.assumeIsolated {
            for code in codes { onCode?(code) }
        }
    }
}

/// The session crosses to the camera queue; AVFoundation allows that.
private struct SessionBox: @unchecked Sendable {
    let session: AVCaptureSession
}

/// What the camera sees, filling its frame.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// QR codes in a picture, such as a screenshot of a shop's code.
enum QRImage {
    static func codes(in data: Data) async -> [String] {
        var request = DetectBarcodesRequest()
        request.symbologies = [.qr]
        let found = (try? await request.perform(on: data))?.compactMap(\.payloadString) ?? []
        // Vision's detector can fail to start (it always does in the
        // Simulator); Core Image's older one still reads QR codes.
        return found.isEmpty ? coreImageCodes(in: data) : found
    }

    private static func coreImageCodes(in data: Data) -> [String] {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        else { return [] }
        return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    }
}
