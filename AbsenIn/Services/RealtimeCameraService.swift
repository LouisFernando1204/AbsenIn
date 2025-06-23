// RealtimeCameraService.swift (FINAL - BERSIH - TANPA API ANEH)

import AVFoundation
import Vision
import SwiftUI

protocol RealtimeCameraServiceDelegate: AnyObject {
    @MainActor func cameraService(didDetect observations: [VNFaceObservation], recognizedUsers: [UUID: User?])
}

struct CachedUser {
    let user: User
    let featurePrints: [VNFeaturePrintObservation]
}

class RealtimeCameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let session = AVCaptureSession()
    weak var delegate: RealtimeCameraServiceDelegate?
    
    private(set) var videoDevice: AVCaptureDevice?
    private var videoOutput = AVCaptureVideoDataOutput()
    private var isPrepared = false
    
    private var cachedUsers: [CachedUser] = []
    
    private var isProcessingFrame = false
    private var isRecognitionLocked = false

    func updateRegisteredUsers(_ users: [User]) {
        cachedUsers = users.compactMap { user in
            guard let data = user.facialVectorData,
                  let prints = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [VNFeaturePrintObservation] else {
                return nil
            }
            return CachedUser(user: user, featurePrints: prints)
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
        } catch { return false }
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

    // =================================================================
    // KEMBALI KE LOGIKA YANG SEDERHANA DAN BENAR
    // =================================================================
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessingFrame, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        isProcessingFrame = true
        
        // HANYA DETEKSI KOTAK WAJAH. TIDAK PERLU LANDMARKS.
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { [weak self] (request, error) in
            guard let self = self,
                  let faceObservations = request.results as? [VNFaceObservation],
                  !faceObservations.isEmpty else {
                
                DispatchQueue.main.async { self?.delegate?.cameraService(didDetect: [], recognizedUsers: [:]) }
                self?.isProcessingFrame = false
                return
            }
            
            // Proses wajah yang ditemukan
            self.process(faceObservations: faceObservations, in: pixelBuffer)
        }
        faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3

        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            try handler.perform([faceDetectionRequest])
        } catch {
            print("Gagal deteksi wajah: \(error)")
            isProcessingFrame = false
        }
    }

    private func process(faceObservations: [VNFaceObservation], in pixelBuffer: CVPixelBuffer) {
        if isRecognitionLocked {
            DispatchQueue.main.async {
                self.delegate?.cameraService(didDetect: faceObservations, recognizedUsers: [:])
            }
            isProcessingFrame = false
            return
        }

        let recognitionHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        var recognitionResults: [UUID: User?] = [:]
        let dispatchGroup = DispatchGroup()

        for face in faceObservations {
            dispatchGroup.enter()
            
            let featurePrintRequest = VNGenerateImageFeaturePrintRequest()
            // GUNAKAN regionOfInterest, INI CARA YANG BENAR.
            featurePrintRequest.regionOfInterest = face.boundingBox

            do {
                try recognitionHandler.perform([featurePrintRequest])
                if let liveFeaturePrint = featurePrintRequest.results?.first {
                    let recognizedUser = self.verify(liveFeaturePrint: liveFeaturePrint)
                    recognitionResults[face.uuid] = recognizedUser
                    
                    if recognizedUser != nil {
                        self.isRecognitionLocked = true
                    }
                } else {
                    recognitionResults[face.uuid] = nil
                }
            } catch {
                recognitionResults[face.uuid] = nil
            }
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .global()) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.cameraService(didDetect: faceObservations, recognizedUsers: recognitionResults)
                if self.isRecognitionLocked {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        self.isRecognitionLocked = false
                    }
                }
                self.isProcessingFrame = false
            }
        }
    }

    private func verify(liveFeaturePrint: VNFeaturePrintObservation) -> User? {
        var closestMatch: (user: User, distance: Float)? = nil

        for cachedUser in self.cachedUsers {
            var bestDistanceForThisUser: Float = .greatestFiniteMagnitude
            
            for storedPrint in cachedUser.featurePrints {
                do {
                    var distance: Float = 0.0
                    try liveFeaturePrint.computeDistance(&distance, to: storedPrint)
                    
                    if distance < bestDistanceForThisUser {
                        bestDistanceForThisUser = distance
                    }
                } catch { continue }
            }
            
            if closestMatch == nil || bestDistanceForThisUser < closestMatch!.distance {
                closestMatch = (user: cachedUser.user, distance: bestDistanceForThisUser)
            }
        }
        
        guard let bestMatch = closestMatch else { return nil }
        
        // KUNCI UTAMA ADA DI SINI. KITA PAKAI THRESHOLD SUPER KETAT.
        let threshold: Float = 0.8
        
        print("Jarak terdekat: \(bestMatch.user.name) (\(String(format: "%.4f", bestMatch.distance))) | Ambang batas: \(threshold)")
        
        if bestMatch.distance < threshold {
            return bestMatch.user
        } else {
            return nil
        }
    }
}
