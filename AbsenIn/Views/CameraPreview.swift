import SwiftUI
import AVFoundation
import UIKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let videoDevice: AVCaptureDevice?
    let videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView(session: session, device: videoDevice)
        view.previewLayer.videoGravity = self.videoGravity
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

class CameraPreviewUIView: UIView {
    let previewLayer: AVCaptureVideoPreviewLayer
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    init(session: AVCaptureSession, device: AVCaptureDevice?) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        
        self.layer.addSublayer(previewLayer)
        
        if let device = device {
            self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: self.previewLayer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = self.bounds
        updateVideoOrientation()
    }
    
    private func updateVideoOrientation() {
        guard let interfaceOrientation = self.window?.windowScene?.interfaceOrientation else { return }
        
        let videoRotationAngle: CGFloat
        
        switch interfaceOrientation {
        case .portrait:
            videoRotationAngle = 90
        case .portraitUpsideDown:
            videoRotationAngle = 270
        case .landscapeRight:
            videoRotationAngle = 180
        case .landscapeLeft:
            videoRotationAngle = 0
        case .unknown:
            // Jika orientasi tidak diketahui, default ke potret.
            videoRotationAngle = 90
        default:
            // Default ini akan menangkap kasus-kasus baru di masa depan
            // dan menjamin switch ini 100% exhaustive.
            videoRotationAngle = 90
        }
        
        previewLayer.connection?.videoRotationAngle = videoRotationAngle
    }
}
