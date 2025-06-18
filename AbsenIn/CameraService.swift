//
//  CameraService.swift
//  AbsenIn
//
//  Created by Hayya U on 18/06/25.
//
import AVFoundation

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

