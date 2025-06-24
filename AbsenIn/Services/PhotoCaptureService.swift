import AVFoundation
import UIKit

class PhotoCaptureService: NSObject, AVCapturePhotoCaptureDelegate {
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
            print("Front camera not found.")
            return
        }
        self.videoDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
        } catch {
            print("Failed to create camera input: \(error)")
            return
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        
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
        
        // FIX: Ensure the settings are compatible with the delegate.
        let settings = AVCapturePhotoSettings()
        
        // FIX: The orientation of the output photo's data must be set correctly.
        // This ensures the image data itself is oriented properly for Vision analysis.
        if let connection = photoOutput.connection(with: .video) {
            // This is the rotation for portrait holding
            if connection.isVideoRotationAngleSupported(90) {
                 connection.videoRotationAngle = 90
            }
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            print("Failed to process photo: \(error?.localizedDescription ?? "unknown error")")
            photoCaptureCompletion?(nil)
            return
        }
        photoCaptureCompletion?(image)
    }
}
