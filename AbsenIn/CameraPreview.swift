//
//  CameraPreview.swift
//  AbsenIn
//
//  Created by Hayya U on 17/06/25.
//

import Foundation
import SwiftUI
import AVFoundation

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
