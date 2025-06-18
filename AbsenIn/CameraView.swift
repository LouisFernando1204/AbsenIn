//
//  CameraView.swift
//  AbsenIn
//
//  Created by Louis Fernando on 17/06/25.
//

import SwiftUI
import AVFoundation

// MARK: - UIViewRepresentable (Jembatan ke SwiftUI)
struct CameraView: UIViewRepresentable {
    @Binding var capturedImage: UIImage?
    let cameraService: CameraService

    func makeUIView(context: Context) -> CameraPreviewUIView {
        // Panggil fungsi start dari service kamera
        cameraService.start(delegate: context.coordinator) { err in
            if let err = err {
                print("Error starting camera: \(err.localizedDescription)")
            }
        }
        
        // Sekarang kita hanya perlu membuat dan mengembalikan CameraPreviewUIView kita.
        // Kita berikan session dari service ke view kustom kita.
        return CameraPreviewUIView(session: cameraService.session)
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Biarkan kosong untuk sekarang
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator (Delegate Handler)
    class Coordinator: NSObject, AVCapturePhotoCaptureDelegate {
        var parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            guard error == nil else {
                print("Error capturing photo: \(error!)")
                return
            }
            
            if let imageData = photo.fileDataRepresentation(), let image = UIImage(data: imageData) {
                DispatchQueue.main.async {
                    self.parent.capturedImage = image
                }
            }
        }
    }
}


// MARK: - UIView Kustom untuk Preview Kamera
class CameraPreviewUIView: UIView {
    
    private var previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        
        self.previewLayer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(previewLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Setiap kali layout diperbarui, pastikan frame layer sama dengan bounds view.
        previewLayer.frame = self.bounds
    }
}


// MARK: - Service untuk Mengelola Sesi Kamera
class CameraService {
    var session = AVCaptureSession()
    var delegate: AVCapturePhotoCaptureDelegate?
    let output = AVCapturePhotoOutput()
    // Kita tidak perlu lagi properti 'preview' di sini karena sudah dikelola oleh CameraPreviewUIView
    // var preview = AVCaptureVideoPreviewLayer() // << HAPUS ATAU KOMENTARI BARIS INI
    
    func start(delegate: AVCapturePhotoCaptureDelegate, completion: @escaping (Error?) -> ()) {
        self.delegate = delegate
        checkPermissions(completion: completion)
    }
    
    private func checkPermissions(completion: @escaping (Error?) -> ()) {
        setupCamera(completion: completion)
    }
    
    private func setupCamera(completion: @escaping (Error?) -> ()) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("Front camera is not available.")
            return
        }
        
        session.beginConfiguration()
        
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        
        session.sessionPreset = .photo
        session.commitConfiguration()
        
        // Kita tidak lagi mengatur 'preview.session' di sini, karena sudah dilakukan di init CameraPreviewUIView
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }
    
    func capturePhoto() {
        guard let delegate = self.delegate else {
            print("Camera delegate is not set.")
            return
        }
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: delegate)
    }
}
