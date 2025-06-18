//
//  CameraPreview.swift
//  AbsenIn
//
//  Created by Hayya U on 17/06/25.
//

import Foundation
import SwiftUI
import AVFoundation

<<<<<<< Updated upstream
<<<<<<< Updated upstream
struct CameraPreview: UIViewRepresentable {
    
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        let preview_layer = AVCaptureVideoPreviewLayer(session: session)
        preview_layer.videoGravity = .resizeAspectFill
        preview_layer.connection?.videoOrientation = .portrait
        
        view.layer.addSublayer(preview_layer)
        
        // Pastikan layer mengikuti ukuran view
        DispatchQueue.main.async {
            preview_layer.frame = view.bounds
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update view jika ada perubahan state di SwiftUI
        // Untuk preview sederhana, kita bisa biarkan kosong
        // Atau kita bisa pastikan lagi frame nya benar
        if let preview_layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            preview_layer.frame = uiView.bounds
        }
    }
}
=======
=======
>>>>>>> Stashed changes
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
>>>>>>> Stashed changes
