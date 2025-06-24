//// IMPROVED: RealtimeCameraService.swift - Better face detection
//import AVFoundation
//import Vision
//import SwiftUI
//import VideoToolbox
//
//class ImprovedRealtimeCameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
//    let session = AVCaptureSession()
//    weak var delegate: RealtimeCameraServiceDelegate?
//    private(set) var videoDevice: AVCaptureDevice?
//    private let videoOutput = AVCaptureVideoDataOutput()
//    private var cachedUsers: [CachedUser] = []
//    private var isProcessingFrame = false
//    private var isRecognitionLocked = false
//    private let sessionQueue = DispatchQueue(label: "sessionQueue", qos: .userInitiated)
//    
//    // IMPROVEMENT 1: Adaptive thresholding based on registration quality
//    private var adaptiveThreshold: Float = 1.0
//    private let baseThreshold: Float = 0.8
//    private let maxThreshold: Float = 1.2
//    
//    func updateRegisteredUsers(_ users: [User]) {
//        cachedUsers = users.compactMap { user in
//            guard let embedding = user.getEmbedding() else { return nil }
//            return CachedUser(user: user, embedding: embedding)
//        }
//        
//        // IMPROVEMENT 2: Calculate adaptive threshold based on registration diversity
//        calculateAdaptiveThreshold()
//        print("✅ Scanner ready with \(cachedUsers.count) users. Threshold: \(adaptiveThreshold)")
//    }
//    
//    private func calculateAdaptiveThreshold() {
//        guard cachedUsers.count > 1 else {
//            adaptiveThreshold = baseThreshold
//            return
//        }
//        
//        // Calculate minimum distance between any two registered users
//        var minInterUserDistance: Float = Float.greatestFiniteMagnitude
//        
//        for i in 0..<cachedUsers.count {
//            for j in (i+1)..<cachedUsers.count {
//                let distance = cachedUsers[i].embedding.euclideanDistance(to: cachedUsers[j].embedding)
//                minInterUserDistance = min(minInterUserDistance, distance)
//            }
//        }
//        
//        // Set threshold to 60% of minimum inter-user distance, within bounds
//        adaptiveThreshold = max(baseThreshold, min(maxThreshold, minInterUserDistance * 0.6))
//    }
//    
//    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
//        guard !isProcessingFrame, !isRecognitionLocked, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
//        isProcessingFrame = true
//        
//        // IMPROVEMENT 3: Use standard face rectangles for better real-time performance
//        let faceRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
//            guard let self = self else { return }
//            guard let results = request.results as? [VNFaceObservation] else {
//                self.finishFrame(with: .searching)
//                return
//            }
//            
//            if results.count > 1 {
//                self.finishFrame(with: .multipleFaces)
//                return
//            }
//            
//            guard let face = results.first else {
//                self.finishFrame(with: .searching)
//                return
//            }
//            
//            // IMPROVEMENT 4: Better quality assessment
//            self.assessFaceQuality(face: face, in: pixelBuffer)
//        }
//        
//        // IMPROVEMENT 5: Configure for better accuracy
//        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
//        
//        do {
//            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
//            try handler.perform([faceRequest])
//        } catch {
//            self.finishFrame(with: .searching)
//        }
//    }
//    
//    // IMPROVEMENT 6: Enhanced quality assessment
//    private func assessFaceQuality(face: VNFaceObservation, in pixelBuffer: CVPixelBuffer) {
//        // Check bounding box size (face should be reasonably large)
//        let imageSize = CVImageBufferGetDisplaySize(pixelBuffer)
//        let faceRect = VNImageRectForNormalizedRect(face.boundingBox, Int(imageSize.width), Int(imageSize.height))
//        let minFaceSize: CGFloat = 80 // Minimum face size in pixels
//        
//        guard faceRect.width >= minFaceSize && faceRect.height >= minFaceSize else {
//            self.finishFrame(with: .lowQuality(face, pixelBuffer))
//            return
//        }
//        
//        // Check if face is too close to edges (might be cut off)
//        let edgeThreshold: Double = 0.05
//        guard face.boundingBox.minX > edgeThreshold &&
//              face.boundingBox.minY > edgeThreshold &&
//              face.boundingBox.maxX < (1.0 - edgeThreshold) &&
//              face.boundingBox.maxY < (1.0 - edgeThreshold) else {
//            self.finishFrame(with: .lowQuality(face, pixelBuffer))
//            return
//        }
//        
//        self.lockAndVerify(face: face, in: pixelBuffer)
//    }
//    
//    private func lockAndVerify(face: VNFaceObservation, in pixelBuffer: CVPixelBuffer) {
//        isRecognitionLocked = true
//        DispatchQueue.main.async { self.delegate?.cameraService(didProduce: .verifying) }
//        
//        guard let image = CGImage.create(from: pixelBuffer) else {
//            unlockAndFinish(with: .noMatch(face, pixelBuffer))
//            return
//        }
//        
//        ImprovedFaceNetService.shared.generateEmbedding(from: image, for: face) { [weak self] values in
//            guard let self = self, let values = values else {
//                self?.unlockAndFinish(with: .noMatch(face, pixelBuffer))
//                return
//            }
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
//    // IMPROVEMENT 7: Enhanced verification with multiple metrics
//    private func verify(liveVector: FacialVector) -> User? {
//        guard !cachedUsers.isEmpty else { return nil }
//        
//        var candidates: [(user: User, euclidean: Float, cosine: Float)] = []
//        
//        for cachedUser in cachedUsers {
//            let euclidean = liveVector.euclideanDistance(to: cachedUser.embedding)
//            let cosine = liveVector.cosineDistance(to: cachedUser.embedding)
//            candidates.append((cachedUser.user, euclidean, cosine))
//        }
//        
//        // Sort by euclidean distance (primary metric)
//        candidates.sort { $0.euclidean < $1.euclidean }
//        
//        guard let bestCandidate = candidates.first else { return nil }
//        
//        print("--- VERIFICATION RESULTS ---")
//        print("Best candidate: \(bestCandidate.user.name)")
//        print("Euclidean: \(String(format: "%.4f", bestCandidate.euclidean))")
//        print("Cosine: \(String(format: "%.4f", bestCandidate.cosine))")
//        print("Threshold: \(adaptiveThreshold)")
//        
//        // IMPROVEMENT 8: Multi-metric validation
//        let passesEuclidean = bestCandidate.euclidean < adaptiveThreshold
//        let passesCosine = bestCandidate.cosine < 0.4 // Cosine distance threshold
//        
//        // Require both metrics to agree for high confidence
//        if passesEuclidean && passesCosine {
//            print("✅ MATCH CONFIRMED (both metrics)")
//            return bestCandidate.user
//        } else if passesEuclidean && candidates.count > 1 {
//            // Check if there's a clear winner (distance gap)
//            let secondBest = candidates[1]
//            let distanceGap = secondBest.euclidean - bestCandidate.euclidean
//            
//            if distanceGap > 0.2 { // Significant gap
//                print("✅ MATCH CONFIRMED (clear winner)")
//                return bestCandidate.user
//            }
//        }
//        
//        print("❌ NO MATCH")
//        return nil
//    }
//    
//    private func finishFrame(with result: ScanResult) {
//        DispatchQueue.main.async { self.delegate?.cameraService(didProduce: result) }
//        isProcessingFrame = false
//    }
//    
//    private func unlockAndFinish(with result: ScanResult) {
//        DispatchQueue.main.async {
//            self.delegate?.cameraService(didProduce: result)
//            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { // Reduced lock time
//                self.isRecognitionLocked = false
//            }
//        }
//        isProcessingFrame = false
//    }
//}
//
//// IMPROVEMENT 9: Extended FacialVector with cosine distance
//extension FacialVector {
//    func cosineDistance(to other: FacialVector) -> Float {
//        guard values.count == other.values.count else { return 1.0 }
//        
//        let dotProduct = zip(values, other.values).map(*).reduce(0, +)
//        let normA = sqrt(values.map { $0 * $0 }.reduce(0, +))
//        let normB = sqrt(other.values.map { $0 * $0 }.reduce(0, +))
//        
//        guard normA > 0 && normB > 0 else { return 1.0 }
//        
//        let cosineSimilarity = dotProduct / (normA * normB)
//        return 1.0 - cosineSimilarity // Convert to distance
//    }
//    
//    // IMPROVEMENT 10: Magnitude for debugging
//    var magnitude: Float {
//        return sqrt(values.map { $0 * $0 }.reduce(0, +))
//    }
//}
//
//// IMPROVEMENT 11: Better preprocessing with configurable normalization
//class ImprovedFaceNetService {
//    static let shared = ImprovedFaceNetService()
//    private var coreMLModel: FaceNetModel?
//    
//    // CRITICAL: Configure this based on your Core ML model's requirements!
//    private enum NormalizationType {
//        case zeroToOne          // [0, 1]
//        case minusOneToOne      // [-1, 1] (your current)
//        case imageNet           // ImageNet mean/std
//    }
//    
//    private let normalizationType: NormalizationType = .minusOneToOne // Change as needed!
//    
//    private init() {
//        do {
//            coreMLModel = try FaceNetModel(configuration: MLModelConfiguration())
//            print("✅ ImprovedFaceNetModel loaded successfully.")
//        } catch {
//            print("❌ FATAL ERROR: Failed to load FaceNetModel: \(error)")
//            coreMLModel = nil
//        }
//    }
//    
//    func generateEmbedding(from fullImage: CGImage, for faceObservation: VNFaceObservation, completion: @escaping ([Float]?) -> Void) {
//        guard let model = self.coreMLModel else {
//            print("❌ Model not loaded")
//            completion(nil)
//            return
//        }
//        
//        DispatchQueue.global(qos: .userInitiated).async {
//            guard let multiArray = self.improvedPreprocess(image: fullImage, observation: faceObservation) else {
//                DispatchQueue.main.async { completion(nil) }
//                return
//            }
//            
//            do {
//                let input = FaceNetModelInput(input: multiArray)
//                let predictionOutput = try model.prediction(input: input)
//                let embedding = predictionOutput.embeddings.toFloatArray()
//                
//                // IMPROVEMENT 12: L2 normalization of embeddings
//                let normalizedEmbedding = self.l2Normalize(embedding)
//                
//                DispatchQueue.main.async { completion(normalizedEmbedding) }
//            } catch {
//                print("❌ Prediction failed: \(error)")
//                DispatchQueue.main.async { completion(nil) }
//            }
//        }
//    }
//    
//    private func improvedPreprocess(image: CGImage, observation: VNFaceObservation) -> MLMultiArray? {
//        let targetSize = 160
//        
//        // IMPROVEMENT 13: Add padding to face crop for better context
//        let paddingRatio: CGFloat = 0.2 // 20% padding
//        var paddedBoundingBox = observation.boundingBox
//        
//        let horizontalPadding = paddedBoundingBox.width * paddingRatio
//        let verticalPadding = paddedBoundingBox.height * paddingRatio
//        
//        paddedBoundingBox.origin.x -= horizontalPadding / 2
//        paddedBoundingBox.origin.y -= verticalPadding / 2
//        paddedBoundingBox.size.width += horizontalPadding
//        paddedBoundingBox.size.height += verticalPadding
//        
//        // Clamp to image bounds
//        paddedBoundingBox = paddedBoundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
//        
//        let imageRect = VNImageRectForNormalizedRect(paddedBoundingBox, image.width, image.height)
//        guard let croppedImage = image.cropping(to: imageRect) else { return nil }
//        guard let resizedImage = croppedImage.resized(to: CGSize(width: targetSize, height: targetSize)) else { return nil }
//        
//        return normalizeAndConvertToMultiArray(image: resizedImage)
//    }
//    
//    private func normalizeAndConvertToMultiArray(image: CGImage) -> MLMultiArray? {
//        let targetSize = 160
//        
//        do {
//            let multiArray = try MLMultiArray(shape: [1, NSNumber(value: targetSize), NSNumber(value: targetSize), 3], dataType: .float32)
//            
//            var pixelBuffer: CVPixelBuffer?
//            let status = CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
//            guard status == kCVReturnSuccess, let finalPixelBuffer = pixelBuffer else { return nil }
//            
//            CVPixelBufferLockBaseAddress(finalPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
//            let pixelData = CVPixelBufferGetBaseAddress(finalPixelBuffer)
//            
//            let context = CGContext(data: pixelData, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(finalPixelBuffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
//            
//            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
//            
//            CVPixelBufferLockBaseAddress(finalPixelBuffer, .readOnly)
//            defer { CVPixelBufferUnlockBaseAddress(finalPixelBuffer, .readOnly) }
//            guard let baseAddress = CVPixelBufferGetBaseAddress(finalPixelBuffer) else { return nil }
//            let byteBuffer = baseAddress.assumingMemoryBound(to: UInt8.self)
//            
//            for i in 0..<(targetSize * targetSize) {
//                let pixelIndex = i * 4
//                
//                // Extract RGB values (BGRA format)
//                let rawR = Float(byteBuffer[pixelIndex + 2])
//                let rawG = Float(byteBuffer[pixelIndex + 1])
//                let rawB = Float(byteBuffer[pixelIndex + 0])
//                
//                // IMPROVEMENT 14: Configurable normalization
//                let (r, g, b) = normalizePixel(r: rawR, g: rawG, b: rawB)
//                
//                let y = i / targetSize
//                let x = i % targetSize
//                
//                multiArray[[0, y as NSNumber, x as NSNumber, 0]] = NSNumber(value: r)
//                multiArray[[0, y as NSNumber, x as NSNumber, 1]] = NSNumber(value: g)
//                multiArray[[0, y as NSNumber, x as NSNumber, 2]] = NSNumber(value: b)
//            }
//            
//            CVPixelBufferUnlockBaseAddress(finalPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
//            return multiArray
//        } catch {
//            print("❌ Error creating MLMultiArray: \(error)")
//            return nil
//        }
//    }
//    
//    private func normalizePixel(r: Float, g: Float, b: Float) -> (Float, Float, Float) {
//        switch normalizationType {
//        case .zeroToOne:
//            return (r / 255.0, g / 255.0, b / 255.0)
//        case .minusOneToOne:
//            return ((r / 255.0 - 0.5) * 2.0, (g / 255.0 - 0.5) * 2.0, (b / 255.0 - 0.5) * 2.0)
//        case .imageNet:
//            // ImageNet normalization
//            let normalizedR = (r / 255.0 - 0.485) / 0.229
//            let normalizedG = (g / 255.0 - 0.456) / 0.224
//            let normalizedB = (b / 255.0 - 0.406) / 0.225
//            return (normalizedR, normalizedG, normalizedB)
//        }
//    }
//    
//    // IMPROVEMENT 15: L2 normalization of embeddings
//    private func l2Normalize(_ embedding: [Float]) -> [Float] {
//        let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
//        guard magnitude > 0 else { return embedding }
//        return embedding.map { $0 / magnitude }
//    }
//}
