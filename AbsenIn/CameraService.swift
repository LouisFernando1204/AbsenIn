//
//  CameraService.swift
//  AbsenIn
//
//  Created by Hayya U on 17/06/25.
//

import Foundation
import AVFoundation
import Combine // Import Combine to use @Published

class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    
    var session = AVCaptureSession()
    private var photo_output = AVCapturePhotoOutput()
    private var current_camera_position: AVCaptureDevice.Position = .back
    
    @Published var photo_data: Data?

    override init() {
        super.init()
        checkPermissions()
    }
    
    // Function to check camera permissions
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupSession()
                    }
                }
            }
        default:
            print("Camera Permission Denied")
        }
    }
    
    // function to setup camera session
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Input
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: current_camera_position),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("Could not find camera for position: \(current_camera_position)")
            session.commitConfiguration()
            return
        }
        
        // Output
        if session.canAddInput(input) && session.canAddOutput(photo_output) {
            session.addInput(input)
            session.addOutput(photo_output)
        }
        
        session.commitConfiguration()
    }
    
    // Function to Start session
    func startSession() {
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
    }
    
    // Function to Stop session
    func stopSession() {
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    func flipCamera() {
        // Tentukan posisi kamera baru
        let new_position: AVCaptureDevice.Position = (current_camera_position == .back) ? .front : .back
        
        // Find camera for the new input position
        guard let new_device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: new_position) else {
            print("Could not find camera for position: \(new_position)")
            return
        }
        
        // start session configuration
        session.beginConfiguration()
        
        // delete the old input
        if let current_input = session.inputs.first {
            session.removeInput(current_input)
        }
        
        // add the new input
        do {
            let new_input = try AVCaptureDeviceInput(device: new_device)
            if session.canAddInput(new_input) {
                session.addInput(new_input)
                // Update current camera position
                self.current_camera_position = new_position
            }
        } catch {
            print("Failed to create new camera input: \(error.localizedDescription)")
        }
        
        // Selesaikan konfigurasi session
        session.commitConfiguration()
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        // Call delegate in it's own class
        photo_output.capturePhoto(with: settings, delegate: self)
    }
    
    // Delegate method from AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation() else {
            print("Coulndn't get data from photo \(error?.localizedDescription ?? "Error Unknown")")
            return
        }
        
        // publish photo data using @Published property
        DispatchQueue.main.async {
            self.photo_data = data
        }
    }
}
