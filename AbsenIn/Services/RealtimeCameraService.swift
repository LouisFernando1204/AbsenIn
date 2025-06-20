import AVFoundation
import Vision
import SwiftUI
import UIKit

// This extension is correct and provides orientation helpers for the app.
extension UIDeviceOrientation {
    var videoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight
        case .landscapeRight: return .landscapeLeft
        default: return .portrait
        }
    }
    
    var visionOrientation: CGImagePropertyOrientation {
        switch self {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .up
        case .landscapeRight: return .down
        default: return .right
        }
    }
}

// THE FIX: The DetectedFace struct is restored here, where it's created.
struct DetectedFace: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let name: String?
    let color: Color
    let recognizedUser: User?
}

protocol RealtimeCameraServiceDelegate: AnyObject {
    @MainActor func cameraService(didDetect faces: [DetectedFace])
}

struct CachedUser {
    let user: User
    let faceprints: [VNFeaturePrintObservation]
}

class RealtimeCameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let session = AVCaptureSession()
    weak var delegate: RealtimeCameraServiceDelegate?
    
    private var isPrepared = false
    private let strictRecognitionThreshold: Float = 0.68
    private let uncertaintyThreshold: Float = 0.74
    private let landmarkSimilarityThreshold: Float = 0.9
    
    private var cachedUsers: [CachedUser] = []
    private var isProcessingFrame = false
    
    func updateRegisteredUsers(_ users: [User]) {
        cachedUsers = users.compactMap { user in
            guard let data = user.faceprintData,
                  let prints = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, VNFeaturePrintObservation.self], from: data) as? [VNFeaturePrintObservation],
                  user.faceLandmarksData != nil else {
                return nil
            }
            return CachedUser(user: user, faceprints: prints)
        }
    }
    
    func prepare(completion: @escaping (Bool) -> Void) {
        if isPrepared {
            completion(true)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let success = self.setupSession()
            if success {
                self.isPrepared = true
            }
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
    
    private func setupSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return false }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) } else { return false }
        } catch {
            print("Gagal membuat input kamera: \(error)"); return false
        }
        
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
        
        let visionOrientation = UIDevice.current.orientation.visionOrientation

        let faceLandmarksRequest = VNDetectFaceLandmarksRequest { (request, error) in
            defer { self.isProcessingFrame = false }
            
            guard let faceObservations = request.results as? [VNFaceObservation] else {
                DispatchQueue.main.async { self.delegate?.cameraService(didDetect: []) }
                return
            }
            
            self.process(faceObservations: faceObservations, in: pixelBuffer, orientation: visionOrientation)
        }
        
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: visionOrientation).perform([faceLandmarksRequest])
        } catch {
            print("Gagal melakukan request deteksi wajah: \(error)"); isProcessingFrame = false
        }
    }
    
    private func process(faceObservations: [VNFaceObservation], in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        let dispatchGroup = DispatchGroup()
        var recognitionResults: [DetectedFace] = []
        
        for faceObservation in faceObservations {
            dispatchGroup.enter()
            let featureprintRequest = VNGenerateImageFeaturePrintRequest()
            
            do {
                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
                try handler.perform([featureprintRequest])
                
                guard let landmarks = faceObservation.landmarks,
                      let featurePrint = featureprintRequest.results?.first as? VNFeaturePrintObservation else {
                    dispatchGroup.leave()
                    continue
                }
                
                if let verifiedUser = self.verify(liveFeaturePrint: featurePrint, liveLandmarks: landmarks) {
                    recognitionResults.append(DetectedFace(boundingBox: faceObservation.boundingBox, name: verifiedUser.name, color: .green, recognizedUser: verifiedUser))
                } else {
                    recognitionResults.append(DetectedFace(boundingBox: faceObservation.boundingBox, name: "Tidak Dikenali", color: .red, recognizedUser: nil))
                }
                
            } catch {
                print("Gagal melakukan analisis detail wajah: \(error)")
            }
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .global()) {
            DispatchQueue.main.async {
                self.delegate?.cameraService(didDetect: recognitionResults)
            }
        }
    }
    
    private func verify(liveFeaturePrint: VNFeaturePrintObservation, liveLandmarks: VNFaceLandmarks2D) -> User? {
        var bestMatch: (user: User, distance: Float)? = nil
        for cachedUser in self.cachedUsers {
            var lowestDistanceForThisUser: Float = .greatestFiniteMagnitude
            for storedPrint in cachedUser.faceprints {
                var distance: Float = .greatestFiniteMagnitude
                try? liveFeaturePrint.computeDistance(&distance, to: storedPrint)
                lowestDistanceForThisUser = min(lowestDistanceForThisUser, distance)
            }
            if bestMatch == nil || lowestDistanceForThisUser < bestMatch!.distance {
                bestMatch = (cachedUser.user, lowestDistanceForThisUser)
            }
        }
        
        if let best = bestMatch {
            if best.distance < self.strictRecognitionThreshold { return best.user }
            if best.distance < self.uncertaintyThreshold,
               let storedLandmarksData = best.user.faceLandmarksData,
               let storedLandmarks = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFaceLandmarks2D.self, from: storedLandmarksData) {
                let similarity = self.calculateLandmarkSimilarity(landmarks1: storedLandmarks, landmarks2: liveLandmarks)
                if similarity > self.landmarkSimilarityThreshold { return best.user }
            }
        }
        return nil
    }
    
    private func calculateLandmarkSimilarity(landmarks1: VNFaceLandmarks2D, landmarks2: VNFaceLandmarks2D) -> Float {
        guard let p1_leftPupil = landmarks1.leftPupil?.normalizedPoints.first, let p1_rightPupil = landmarks1.rightPupil?.normalizedPoints.first, let p1_noseTip = landmarks1.nose?.normalizedPoints.first, let p2_leftPupil = landmarks2.leftPupil?.normalizedPoints.first, let p2_rightPupil = landmarks2.rightPupil?.normalizedPoints.first, let p2_noseTip = landmarks2.nose?.normalizedPoints.first else { return 0.0 }
        let p1_pupilDistance = hypot(p1_rightPupil.x - p1_leftPupil.x, p1_rightPupil.y - p1_leftPupil.y)
        let p2_pupilDistance = hypot(p2_rightPupil.x - p2_leftPupil.x, p2_rightPupil.y - p2_leftPupil.y)
        guard p1_pupilDistance > 0, p2_pupilDistance > 0 else { return 0.0 }
        let p1_leftPupilToNose = hypot(p1_noseTip.x - p1_leftPupil.x, p1_noseTip.y - p1_leftPupil.y) / p1_pupilDistance
        let p2_leftPupilToNose = hypot(p2_noseTip.x - p2_leftPupil.x, p2_noseTip.y - p2_leftPupil.y) / p2_pupilDistance
        let p1_rightPupilToNose = hypot(p1_noseTip.x - p1_rightPupil.x, p1_noseTip.y - p1_rightPupil.y) / p1_pupilDistance
        let p2_rightPupilToNose = hypot(p2_noseTip.x - p2_rightPupil.x, p2_noseTip.y - p2_rightPupil.y) / p2_pupilDistance
        let error1 = abs(p1_leftPupilToNose - p2_leftPupilToNose)
        let error2 = abs(p1_rightPupilToNose - p2_rightPupilToNose)
        let averageError = (error1 + error2) / 2.0
        let similarity = max(0.0, 1.0 - (averageError / 0.1))
        return Float(similarity)
    }
}
