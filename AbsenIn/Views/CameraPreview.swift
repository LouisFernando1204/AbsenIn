import SwiftUI
import AVFoundation
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    // THE FIX: Use a closure to pass the layer back. This is the correct pattern.
    var onLayerCreated: ((AVCaptureVideoPreviewLayer) -> Void)? = nil

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView(session: session)
        view.previewLayer.videoGravity = .resizeAspectFill
        
        // If the closure was provided, call it to pass the layer back.
        if let onLayerCreated = self.onLayerCreated {
            onLayerCreated(view.previewLayer)
        }
        
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

class CameraPreviewUIView: UIView {
    // THE FIX: This is now a standard stored property.
    let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        
        self.layer.addSublayer(previewLayer)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceDidRotate),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    // THE FIX: This required initializer was missing.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateVideoOrientation()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = self.bounds
    }

    @objc private func deviceDidRotate() {
        updateVideoOrientation()
    }

    private func updateVideoOrientation() {
        guard let connection = previewLayer.connection, connection.isVideoOrientationSupported else { return }
        
        guard let scene = self.window?.windowScene else { return }
        let interfaceOrientation = scene.interfaceOrientation
        
        let videoOrientation: AVCaptureVideoOrientation
        switch interfaceOrientation {
        case .portrait:
            videoOrientation = .portrait
        case .portraitUpsideDown:
            videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            videoOrientation = .landscapeLeft
        case .landscapeRight:
            videoOrientation = .landscapeRight
        default:
            videoOrientation = .portrait
        }
        
        connection.videoOrientation = videoOrientation
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
