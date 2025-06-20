import AVFoundation
import UIKit

class PhotoCaptureService: NSObject { // Tambahkan NSObject agar bisa menjadi delegate
    let session = AVCaptureSession()
    
    private(set) var videoDevice: AVCaptureDevice?
    
    private var photoOutput = AVCapturePhotoOutput()
    private var photoCaptureCompletion: ((UIImage?) -> Void)?

    override init() { // Tambahkan override karena kita mewarisi dari NSObject
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
        
        // 2. SIMPAN REFERENSI KE PERANGKAT
        // Ini penting agar View bisa mengaksesnya.
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
        
        session.sessionPreset = .photo
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
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension PhotoCaptureService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let imageData = photo.fileDataRepresentation(), let image = UIImage(data: imageData) else {
            print("Gagal memproses foto: \(error?.localizedDescription ?? "error tidak diketahui")")
            photoCaptureCompletion?(nil)
            return
        }
        photoCaptureCompletion?(image)
    }
}
