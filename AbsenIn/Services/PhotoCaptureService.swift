// PhotoCaptureService.swift (GANTI SELURUH FILE)

import AVFoundation
import UIKit

class PhotoCaptureService: NSObject {
    let session = AVCaptureSession()
    
    private(set) var videoDevice: AVCaptureDevice?
    
    private var photoOutput = AVCapturePhotoOutput()
    private var photoCaptureCompletion: ((UIImage?) -> Void)?

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Kamera depan tidak ditemukan.")
            return
        }
        
        self.videoDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("Gagal membuat input kamera: \(error)")
            return
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        
        // PERBAIKAN PENTING: Samakan preset sesi dengan RealtimeCameraService.
        // Ini sangat krusial untuk konsistensi antara data registrasi dan data scan.
        session.sessionPreset = .hd1920x1080
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

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        self.photoCaptureCompletion = completion
        
        // Cukup buat objek settings standar. iOS akan memilih format terbaik
        // yang kompatibel dengan sesi yang sedang berjalan.
        let settings = AVCapturePhotoSettings()
        
        // Pastikan orientasi foto sesuai dengan preview
        if let connection = photoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension PhotoCaptureService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("Gagal memproses foto: \(error?.localizedDescription ?? "error tidak diketahui")")
            photoCaptureCompletion?(nil)
            return
        }
        photoCaptureCompletion?(image)
    }
}
