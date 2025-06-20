import AVFoundation
import Vision
import SwiftUI
import UIKit

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

struct DetectedFace: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let recognizedUser: User?
}

protocol RealtimeCameraServiceDelegate: AnyObject {
    @MainActor func cameraService(didDetect faces: [DetectedFace])
}

struct CachedUser {
    let user: User
    let facialVectors: [FacialVector]
}

class RealtimeCameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let session = AVCaptureSession()
    weak var delegate: RealtimeCameraServiceDelegate?
    
    private var isPrepared = false
    private let recognitionThreshold: Float = 0.08
    
    // PERBAIKAN UTAMA: Parameter baru untuk mencegah salah identifikasi.
    // Ini adalah jarak minimal yang dibutuhkan antara kandidat terbaik #1 dan #2.
    // Naikkan nilai ini untuk membuatnya lebih ketat.
    private let ambiguityRejectionThreshold: Float = 0.05
    
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
        
        let visionOrientation = UIDevice.current.orientation.visionOrientation

        let faceLandmarksRequest = VNDetectFaceLandmarksRequest { (request, error) in
            defer { self.isProcessingFrame = false }
            
            guard let faceObservations = request.results as? [VNFaceObservation] else {
                DispatchQueue.main.async { self.delegate?.cameraService(didDetect: []) }
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
            DispatchQueue.main.async { self.delegate?.cameraService(didDetect: []) }
            return
        }
        
        let dispatchGroup = DispatchGroup()
        var recognitionResults: [DetectedFace] = []
        
        for face in faceObservations {
            dispatchGroup.enter()
            
            guard let landmarks = face.landmarks, let liveVector = landmarks.toFacialVector() else {
                dispatchGroup.leave()
                continue
            }
            
            let recognizedUser = self.verify(liveVector: liveVector)
            recognitionResults.append(DetectedFace(boundingBox: face.boundingBox, recognizedUser: recognizedUser))
            
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .global()) {
            DispatchQueue.main.async {
                self.delegate?.cameraService(didDetect: recognitionResults)
            }
        }
    }
    
    // PERBAIKAN TOTAL: Logika verifikasi yang benar dengan Penolakan Ambiguitas.
    private func verify(liveVector: FacialVector) -> User? {
        var allMatches: [(user: User, distance: Float)] = []

        // 1. Hitung skor terbaik untuk SETIAP pengguna yang terdaftar.
        for cachedUser in self.cachedUsers {
            var minDistanceForThisUser: Float = .greatestFiniteMagnitude
            
            for storedVector in cachedUser.facialVectors {
                let currentDistance = Float(liveVector.distance(to: storedVector))
                if currentDistance < minDistanceForThisUser {
                    minDistanceForThisUser = currentDistance
                }
            }
            allMatches.append((user: cachedUser.user, distance: minDistanceForThisUser))
        }
        
        // 2. Urutkan semua hasil dari yang terbaik (jarak terendah) ke terburuk.
        allMatches.sort { $0.distance < $1.distance }
        
        // 3. Ambil kandidat terbaik. Jika tidak ada, langsung gagal.
        guard let bestMatch = allMatches.first else {
            return nil
        }
        
        // 4. Periksa apakah kandidat terbaik ini cukup bagus (di bawah ambang batas).
        guard bestMatch.distance < self.recognitionThreshold else {
            return nil
        }
        
        // 5. Logika Anti-Ambiguitas:
        // Jika hanya ada satu pengguna terdaftar, tidak ada ambiguitas. Langsung kembalikan.
        guard allMatches.count > 1 else {
            return bestMatch.user
        }
        
        // Ambil kandidat terbaik kedua.
        let secondBestMatch = allMatches[1]
        
        // Hitung selisih/kesenjangan antara skor terbaik #1 dan #2.
        let gap = secondBestMatch.distance - bestMatch.distance
        
        // Jika kesenjangannya terlalu kecil, berarti sistem "bingung". Tolak pemindaian.
        guard gap > self.ambiguityRejectionThreshold else {
            return nil
        }
        
        // Jika semua pemeriksaan lolos, ini adalah kecocokan yang percaya diri.
        return bestMatch.user
    }
}¡™¡™
