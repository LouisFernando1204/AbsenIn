//
//  PhotoCaptureService.swift
//  AbsenIn
//
//  Created by Louis Fernando on 18/06/25.
//

import SwiftUI
import AVFoundation

// Service yang didedikasikan untuk mengambil satu foto.
class PhotoCaptureService: NSObject, ObservableObject {
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var completionHandler: ((UIImage?) -> Void)?
    
    override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("Kamera depan tidak tersedia.")
            return
        }
        
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.sessionPreset = .photo
        session.commitConfiguration()
    }
    
    func startRunning() {
        DispatchQueue.global(qos: .userInitiated).async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    
    func stopRunning() {
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    // Fungsi untuk mengambil foto dengan completion handler
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        self.completionHandler = completion
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    // Fungsi untuk mendapatkan session untuk ditampilkan di view
    func getSession() -> AVCaptureSession {
        return session
    }
}

extension PhotoCaptureService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            completionHandler?(nil)
            return
        }
        completionHandler?(image)
    }
}


// View yang menggunakan CameraPreviewUIView yang sudah kita buat sebelumnya,
// namun didedikasikan untuk service ini.
struct PhotoCaptureView: UIViewRepresentable {
    let service: PhotoCaptureService
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        // Gunakan kembali CameraPreviewUIView yang kuat
        return CameraPreviewUIView(session: service.getSession())
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}
