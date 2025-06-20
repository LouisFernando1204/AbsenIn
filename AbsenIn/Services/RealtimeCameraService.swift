import AVFoundation
import Vision
import SwiftUI
import UIKit

// PERUBAHAN 1: Struct DetectedFace tidak lagi digunakan oleh delegate ini,
// namun bisa dipertahankan jika digunakan di tempat lain.
struct DetectedFace: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let recognizedUser: User?
}

// PERUBAHAN 2: Ubah delegate untuk mengirim data yang lebih kaya.
// Ini memungkinkan ViewModel untuk melakukan liveness check (deteksi kedipan).
protocol RealtimeCameraServiceDelegate: AnyObject {
    @MainActor func cameraService(didDetect observations: [VNFaceObservation], recognizedUsers: [UUID: User?])
}

struct CachedUser {
    let user: User
    let facialVectors: [FacialVector]
}

class RealtimeCameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let session = AVCaptureSession()
    weak var delegate: RealtimeCameraServiceDelegate?
    
    private(set) var videoDevice: AVCaptureDevice?
    private var isPrepared = false
    
    private let recognitionThreshold: Float = 0.09
    private let ambiguityRejectionThreshold: Float = 0.06
    
    private var cachedUsers: [CachedUser] = []
    private var isProcessingFrame = false
    
    func updateRegisteredUsers(_ users: [User]) {
        cachedUsers = users.compactMap { user in
            guard let data = user.facialVectorData,
                  let vectors = try? JSONDecoder().decode([FacialVector].self, from: data) else {
                return nil
            }
            return CachedUser(user: user, facialVectors: vectors)
        }
    }
    
    func prepare(completion: @escaping (Bool) -> Void) {
        if isPrepared { completion(true); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let success = self.setupSession()
            if success { self.isPrepared = true }
            DispatchQueue.main.async { completion(success) }
        }
    }
    
    private func setupSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return false }
        self.videoDevice = device
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) } else { return false }
        } catch { print("Gagal membuat input kamera: \(error)"); return false }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue", qos: .userInitiated))
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) } else { return false }
        
        session.sessionPreset = .hd1920x1080
        return true
    }
    
    func startSession() {
        guard isPrepared, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }
    
    func stopSession() {
        if session.isRunning { session.stopRunning() }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessingFrame, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessingFrame = true
        
        let visionOrientation = visionOrientation(for: connection.videoRotationAngle)

        let faceLandmarksRequest = VNDetectFaceLandmarksRequest { (request, error) in
            defer { self.isProcessingFrame = false }
            
            guard let faceObservations = request.results as? [VNFaceObservation] else {
                DispatchQueue.main.async { self.delegate?.cameraService(didDetect: [], recognizedUsers: [:]) }
                return
            }
            
            self.process(faceObservations: faceObservations)
        }
        
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: visionOrientation).perform([faceLandmarksRequest])
        } catch {
            print("Gagal melakukan request deteksi wajah: \(error)"); isProcessingFrame = false
        }
    }
    
    // PERUBAHAN 3: Ubah fungsi process untuk memanggil delegate yang baru.
    private func process(faceObservations: [VNFaceObservation]) {
        if faceObservations.isEmpty {
            DispatchQueue.main.async {
                self.delegate?.cameraService(didDetect: [], recognizedUsers: [:])
            }
            return
        }
        
        var recognitionResults: [UUID: User?] = [:]
        let dispatchGroup = DispatchGroup()

        for face in faceObservations {
            dispatchGroup.enter()
            guard let landmarks = face.landmarks, let liveVector = landmarks.toFacialVector() else {
                recognitionResults[face.uuid] = nil
                dispatchGroup.leave()
                continue
            }
            
            let recognizedUser = self.verify(liveVector: liveVector)
            recognitionResults[face.uuid] = recognizedUser
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .global()) {
            DispatchQueue.main.async {
                self.delegate?.cameraService(didDetect: faceObservations, recognizedUsers: recognitionResults)
            }
        }
    }
    
    // PERUBAHAN 4: Ganti total fungsi verify dengan logika yang lebih kuat dan adil.
    private func verify(liveVector: FacialVector) -> User? {
        guard !self.cachedUsers.isEmpty else { return nil }

        let allStoredVectors: [(user: User, vector: FacialVector)] = self.cachedUsers.flatMap { cachedUser in
            cachedUser.facialVectors.map { (user: cachedUser.user, vector: $0) }
        }

        guard !allStoredVectors.isEmpty else { return nil }

        var allMatches = allStoredVectors.map { storedData in
            let distance = Float(liveVector.distance(to: storedData.vector))
            return (user: storedData.user, distance: distance)
        }
        
        allMatches.sort { $0.distance < $1.distance }
        
        guard let bestMatch = allMatches.first else {
            return nil
        }
        
        guard bestMatch.distance < self.recognitionThreshold else {
            return nil
        }
        
        guard allMatches.count > 1 else {
            return bestMatch.user
        }
        
        let secondBestMatch = allMatches[1]
        
        if bestMatch.user.id == secondBestMatch.user.id {
            return bestMatch.user
        }
        
        let gap = secondBestMatch.distance - bestMatch.distance
        
        guard gap > self.ambiguityRejectionThreshold else {
            return nil
        }
        
        return bestMatch.user
    }
    
    private func visionOrientation(for videoRotationAngle: CGFloat) -> CGImagePropertyOrientation {
        switch videoRotationAngle {
        case 0: return .up
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .right
        }
    }
}
