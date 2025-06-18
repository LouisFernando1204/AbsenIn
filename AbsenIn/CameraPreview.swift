//
//  CameraPreview.swift
//  AbsenIn
//
//  Created by Louis Fernando on 18/06/25.
//

import SwiftUI
import AVFoundation

// UIView kustom yang tahu cara me-layout layer-nya.
class CameraPreviewUIView: UIView {
    
    private var previewLayer: AVCaptureVideoPreviewLayer
    
    init(session: AVCaptureSession) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        
        previewLayer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(previewLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Metode ini dipanggil setiap kali view perlu menata ulang layout-nya (misal: rotasi).
    override func layoutSubviews() {
        super.layoutSubviews()
        // Atur frame dari previewLayer agar selalu sama persis dengan bounds dari view ini.
        previewLayer.frame = self.bounds
    }
}

// Wrapper UIViewRepresentable yang sederhana.
// Tugasnya hanya membuat dan mengembalikan CameraPreviewUIView kustom kita.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        return CameraPreviewUIView(session: session)
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}
