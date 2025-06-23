import AVFoundation
import Vision
import SwiftUI
import UIKit

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
    
    // We can be a bit more lenient with this threshold because the voting
    // system will filter out random matches.
    private let recognitionThreshold: Float = 0.40
    
    private var cachedUsers: [CachedUser] = []
    private var isProcessingFrame = false
    
    // This function is crucial and is included.
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
    
    // THE KEY FIX: A robust K-Nearest Neighbors (KNN) voting system.
    private func verify(liveVector: FacialVector) -> User? {
        guard !self.cachedUsers.isEmpty else { return nil }

        let allStoredVectors: [(user: User, vector: FacialVector)] = self.cachedUsers.flatMap { cachedUser in
            cachedUser.facialVectors.map { (user: cachedUser.user, vector: $0) }
        }

        guard !allStoredVectors.isEmpty else { return nil }

        // 1. Calculate the distance from the live face to ALL stored vectors.
        var allMatches = allStoredVectors.map { storedData in
            let distance = liveVector.euclideanDistance(to: storedData.vector)
            return (user: storedData.user, distance: distance)
        }
        
        // 2. Sort by the closest distance (smallest is best).
        allMatches.sort { $0.distance < $1.distance }
        
        // 3. Take the top 'k' candidates. Let's use 11 for a clear majority.
        let k = 11
        let nearestNeighbors = allMatches.prefix(k)
        
        // 4. Filter out candidates that are too far away (likely a random person).
        // This is a crucial step to reject unknown faces.
        let validNeighbors = nearestNeighbors.filter { $0.distance < self.recognitionThreshold }
        
        // If no neighbors are close enough, it's an unknown person.
        guard !validNeighbors.isEmpty else { return nil }
        
        // 5. Perform the vote: Count how many times each user ID appears in the valid neighbors.
        // The 'Dictionary(grouping:by:)' is a very efficient way to do this.
        let votes = Dictionary(grouping: validNeighbors, by: { $0.user.id })
            .mapValues { $0.count }
        
        // 6. Find the user with the most votes.
        guard let winner = votes.max(by: { $0.value < $1.value }) else {
            return nil
        }
        
        // 7. Confidence Check: Ensure the winner has a clear majority.
        // The winner must have more than half of the votes to be considered valid.
        let majorityThreshold = validNeighbors.count / 2
        guard winner.value > majorityThreshold else {
            // This handles cases where the votes are split, e.g., 4 votes for Sam, 3 for Lusi.
            // It's too ambiguous, so we reject.
            // print("REJECTED: No clear majority. Winner only has \(winner.value) of \(validNeighbors.count) valid votes.")
            return nil
        }
        
        // 8. Find the full User object for the winning ID.
        return self.cachedUsers.first(where: { $0.user.id == winner.key })?.user
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
