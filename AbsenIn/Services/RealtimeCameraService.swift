//import AVFoundation
//import Vision
//import SwiftUI
//import VideoToolbox
//
//extension CGImage {
//    static func create(from buffer: CVPixelBuffer?) -> CGImage? {
//        guard let buffer = buffer else { return nil }; var cgImage: CGImage?; VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &cgImage); return cgImage
//    }
//}
//
//// --- THE FINAL, CORRECTED ENUM AND PROTOCOL ---
//// The CVPixelBuffer is now available in every case with a single face observation.
//enum ScanResult { case searching, verifying, match(User, VNFaceObservation, CVPixelBuffer), noMatch(VNFaceObservation, CVPixelBuffer), multipleFaces, lowQuality(VNFaceObservation, CVPixelBuffer), error(String) }
//protocol RealtimeCameraServiceDelegate: AnyObject { @MainActor func cameraService(didProduce scanResult: ScanResult) }
//// --- END ---
//
//struct CachedUser { let user: User; let embedding: FacialVector }
//
//class RealtimeCameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
//    let session = AVCaptureSession()
//    weak var delegate: RealtimeCameraServiceDelegate?
//    private(set) var videoDevice: AVCaptureDevice?
//    private let videoOutput = AVCaptureVideoDataOutput()
//    private var cachedUsers: [CachedUser] = []
//    private var isProcessingFrame = false
//    private var isRecognitionLocked = false
//    private let sessionQueue = DispatchQueue(label: "sessionQueue", qos: .userInitiated)
//
//    func updateRegisteredUsers(_ users: [User]) {
//        cachedUsers = users.compactMap { user in
//            guard let embedding = user.getEmbedding() else { return nil }
//            return CachedUser(user: user, embedding: embedding)
//        }
//        print("✅ Scanner ready with \(cachedUsers.count) registered users.")
//    }
//    
//    func prepare() {
//        sessionQueue.async {
//            if self.session.inputs.isEmpty {
//                guard self.setupSession() else {
//                    DispatchQueue.main.async { self.delegate?.cameraService(didProduce: .error("Setup Failed")) }
//                    return
//                }
//            }
//        }
//    }
//    
//    private func setupSession() -> Bool {
//        session.beginConfiguration(); defer { session.commitConfiguration() }
//        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return false }
//        self.videoDevice = device
//        do { let input = try AVCaptureDeviceInput(device: device); if !session.canAddInput(input) { return false }; session.addInput(input) } catch { return false }
//        videoOutput.alwaysDiscardsLateVideoFrames = true
//        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
//        if !session.canAddOutput(videoOutput) { return false }; session.addOutput(videoOutput)
//        session.sessionPreset = .hd1920x1080
//        return true
//    }
//    
//    func startSession() { sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } } }
//    func stopSession() { sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } } }
//
//    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        guard !isProcessingFrame, !isRecognitionLocked, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
//        isProcessingFrame = true
//        
//        // --- THE FINAL, DEFINITIVE FIX ---
//        // We now use the same high-accuracy request for the live scan.
//        // This guarantees the bounding box is generated identically to registration.
//        let detectionRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
//            guard let self = self else { return }
//            guard let results = request.results as? [VNFaceObservation] else { self.finishFrame(with: .searching); return }
//            if results.count > 1 { self.finishFrame(with: .multipleFaces); return }
//            guard let face = results.first else { self.finishFrame(with: .searching); return }
//            
//            // We no longer check for quality here, as lockAndVerify is the only path forward.
//            self.lockAndVerify(face: face, in: pixelBuffer)
//        }
//        // --- END FIX ---
//        
//        do {
//            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
//            try handler.perform([detectionRequest])
//        }
//        catch { self.finishFrame(with: .searching) }
//    }
//    
//    private func finishFrame(with result: ScanResult) {
//        DispatchQueue.main.async { self.delegate?.cameraService(didProduce: result) }
//        isProcessingFrame = false
//    }
//    
//    private func lockAndVerify(face: VNFaceObservation, in pixelBuffer: CVPixelBuffer) {
//        isRecognitionLocked = true
//        DispatchQueue.main.async { self.delegate?.cameraService(didProduce: .verifying) }
//        guard let image = CGImage.create(from: pixelBuffer) else { unlockAndFinish(with: .noMatch(face, pixelBuffer)); return }
//        
//        FaceNetService.shared.generateEmbedding(from: image, for: face) { [weak self] values in
//            guard let self = self, let values = values else { self?.unlockAndFinish(with: .noMatch(face, pixelBuffer)); return }
//
//            // --- EMBEDDING LOGGING (LIVE SCAN) ---
//            let timestamp = Date().formatted(date: .omitted, time: .standard)
//            let vectorPreview = values.prefix(8).map { String(format: "%.4f", $0) }.joined(separator: ", ")
//            print("\n--- 🔬 LIVE SCAN EMBEDDING @ \(timestamp) ---")
//            print("EMBEDDING PREVIEW: [\(vectorPreview)...]")
//            print("--------------------------------------\n")
//            // --- END LOGGING ---
//            
//            let liveVector = FacialVector(values: values)
//            if let user = self.verify(liveVector: liveVector) {
//                self.unlockAndFinish(with: .match(user, face, pixelBuffer))
//            } else {
//                self.unlockAndFinish(with: .noMatch(face, pixelBuffer))
//            }
//        }
//    }
//    
//    private func unlockAndFinish(with result: ScanResult) {
//        DispatchQueue.main.async {
//            self.delegate?.cameraService(didProduce: result)
//            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.isRecognitionLocked = false }
//        }
//        isProcessingFrame = false
//    }
//    
//    private func verify(liveVector: FacialVector) -> User? {
//        guard !cachedUsers.isEmpty else { return nil }
//        let matchThreshold: Float = 1.1
//        var bestMatch: (user: User, distance: Float)? = nil
//        for cachedUser in cachedUsers {
//            let distance = liveVector.euclideanDistance(to: cachedUser.embedding)
//            if bestMatch == nil || distance < bestMatch!.distance {
//                bestMatch = (cachedUser.user, distance)
//            }
//        }
//        guard let finalMatch = bestMatch, finalMatch.distance < matchThreshold else {
//            print("--- ❌ NO MATCH (Closest: \(bestMatch?.user.name ?? "N/A") at \(String(format: "%.4f", bestMatch?.distance ?? -1)))")
//            return nil
//        }
//        print("✅ MATCH CONFIRMED: \(finalMatch.user.name) (Distance: \(String(format: "%.4f", finalMatch.distance)))")
//        return finalMatch.user
//    }
//}
