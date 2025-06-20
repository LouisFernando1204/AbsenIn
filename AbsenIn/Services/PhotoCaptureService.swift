import SwiftUI
import AVFoundation
import UIKit

class PhotoCaptureService: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var completionHandler: ((UIImage?) -> Void)?

    override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        session.sessionPreset = .photo
        session.commitConfiguration()
    }
    
    func startRunning() {
        DispatchQueue.global(qos: .userInitiated).async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }
    
    func stopRunning() {
        if session.isRunning { session.stopRunning() }
    }
    
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        self.completionHandler = completion
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension PhotoCaptureService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let imageData = photo.fileDataRepresentation(), let image = UIImage(data: imageData) else {
            completionHandler?(nil); return
        }
        // The front camera image is mirrored by default, so we flip it to look natural.
        let flippedImage = image.withHorizontallyFlippedOrientation()
        completionHandler?(flippedImage)
    }
}
