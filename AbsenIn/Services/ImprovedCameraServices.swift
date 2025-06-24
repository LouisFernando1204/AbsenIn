import Foundation
import UIKit
import Vision
import Accelerate
import AVFoundation
import CoreML
import VideoToolbox

// MARK: - Helper Extensions (All in one place)

extension CGImage {
    static func create(from buffer: CVPixelBuffer?) -> CGImage? {
        guard let buffer = buffer else { return nil }
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &cgImage)
        return cgImage
    }

    func resized(to size: CGSize) -> CGImage? {
        guard var format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue), renderingIntent: .defaultIntent) else { return nil }
        var sourceBuffer = vImage_Buffer(); defer { sourceBuffer.data.deallocate() }
        var error = vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, self, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { return nil }
        let scale = min(size.width / CGFloat(width), size.height / CGFloat(height))
        let destWidth = Int(CGFloat(width) * scale); let destHeight = Int(CGFloat(height) * scale)
        var destBuffer = vImage_Buffer(); error = vImageBuffer_Init(&destBuffer, UInt(destHeight), UInt(destWidth), format.bitsPerComponent, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { return nil }; defer { destBuffer.data.deallocate() }
        error = vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
        guard error == kvImageNoError else { return nil }
        return try? destBuffer.createCGImage(format: format)
    }
}

extension MLMultiArray {
    func toFloatArray() -> [Float] {
        let count = self.count; let pointer = self.dataPointer.bindMemory(to: Float.self, capacity: count); return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
}

// MARK: - ScanResult, Delegate Protocol, and CachedUser Struct

struct CachedUser { let user: User; let embedding: FacialVector }

enum ScanResult {
    case searching, verifying, match(User, VNFaceObservation, CVPixelBuffer), noMatch(VNFaceObservation, CVPixelBuffer), multipleFaces, lowQuality(VNFaceObservation, CVPixelBuffer), error(String)
}

protocol ImprovedRealtimeCameraServiceDelegate: AnyObject {
    @MainActor func cameraService(didProduce scanResult: ScanResult)
}

// MARK: - ImprovedFaceNetService

class ImprovedFaceNetService {
    static let shared = ImprovedFaceNetService()
    private var coreMLModel: FaceNetModel?
    
    private init() {
        do {
            coreMLModel = try FaceNetModel(configuration: MLModelConfiguration())
            print("✅ ImprovedFaceNetModel loaded successfully.")
        } catch {
            print("❌ FATAL ERROR: Failed to load FaceNetModel: \(error)")
            coreMLModel = nil
        }
    }
    
    func generateEmbedding(from fullImage: CGImage, for faceObservation: VNFaceObservation, completion: @escaping ([Float]?) -> Void) {
        guard let model = self.coreMLModel else { completion(nil); return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let multiArray = self.improvedPreprocess(image: fullImage, observation: faceObservation) else {
                DispatchQueue.main.async { completion(nil) }; return
            }
            do {
                let input = FaceNetModelInput(input: multiArray)
                let predictionOutput = try model.prediction(input: input)
                let embedding = predictionOutput.embeddings.toFloatArray()
                let normalizedEmbedding = self.l2Normalize(embedding)
                DispatchQueue.main.async { completion(normalizedEmbedding) }
            } catch {
                print("❌ Prediction failed: \(error)"); DispatchQueue.main.async { completion(nil) }
            }
        }
    }
    
    private func improvedPreprocess(image: CGImage, observation: VNFaceObservation) -> MLMultiArray? {
        let targetSize = 160
        let paddingRatio: CGFloat = 0.20
        var paddedBoundingBox = observation.boundingBox
        paddedBoundingBox.origin.x -= (paddedBoundingBox.width * paddingRatio) / 2
        paddedBoundingBox.origin.y -= (paddedBoundingBox.height * paddingRatio) / 2
        paddedBoundingBox.size.width *= (1 + paddingRatio)
        paddedBoundingBox.size.height *= (1 + paddingRatio)
        let clampedBoundingBox = paddedBoundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let imageRect = VNImageRectForNormalizedRect(clampedBoundingBox, image.width, image.height)
        guard let croppedImage = image.cropping(to: imageRect) else { return nil }
        guard let resizedImage = croppedImage.resized(to: CGSize(width: targetSize, height: targetSize)) else { return nil }
        return normalizeAndConvertToMultiArray(image: resizedImage)
    }
    
    private func normalizeAndConvertToMultiArray(image: CGImage) -> MLMultiArray? {
        let targetSize = 160
        do {
            let multiArray = try MLMultiArray(shape: [1, 160, 160, 3], dataType: .float32)
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            guard status == kCVReturnSuccess, let finalPixelBuffer = pixelBuffer else { return nil }
            CVPixelBufferLockBaseAddress(finalPixelBuffer, [])
            let pixelData = CVPixelBufferGetBaseAddress(finalPixelBuffer)
            let context = CGContext(data: pixelData, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(finalPixelBuffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let byteBuffer = CVPixelBufferGetBaseAddress(finalPixelBuffer)!.assumingMemoryBound(to: UInt8.self)
            for i in 0..<(targetSize * targetSize) {
                let pixelIndex = i * 4
                let r = (Float(byteBuffer[pixelIndex + 2]) / 255.0 - 0.5) * 2.0
                let g = (Float(byteBuffer[pixelIndex + 1]) / 255.0 - 0.5) * 2.0
                let b = (Float(byteBuffer[pixelIndex + 0]) / 255.0 - 0.5) * 2.0
                let y = i / targetSize; let x = i % targetSize
                multiArray[[0, y, x, 0] as [NSNumber]] = NSNumber(value: r)
                multiArray[[0, y, x, 1] as [NSNumber]] = NSNumber(value: g)
                multiArray[[0, y, x, 2] as [NSNumber]] = NSNumber(value: b)
            }
            CVPixelBufferUnlockBaseAddress(finalPixelBuffer, [])
            return multiArray
        } catch { print("❌ Error creating MLMultiArray: \(error)"); return nil }
    }
    
    private func l2Normalize(_ embedding: [Float]) -> [Float] {
        let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
        guard magnitude > 0 else { return embedding }
        return embedding.map { $0 / magnitude }
    }
}

// MARK: - ImprovedRealtimeCameraService

class ImprovedRealtimeCameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    weak var delegate: ImprovedRealtimeCameraServiceDelegate?
    private let videoOutput = AVCaptureVideoDataOutput()
    private var cachedUsers: [CachedUser] = []
    private var isProcessingFrame = false
    private var isRecognitionLocked = false
    private let sessionQueue = DispatchQueue(label: "sessionQueue", qos: .userInitiated)
    private var adaptiveThreshold: Float = 1.0
    
    func updateRegisteredUsers(_ users: [User]) {
        cachedUsers = users.compactMap { user in
            guard let embedding = user.getEmbedding() else { return nil }
            return CachedUser(user: user, embedding: embedding)
        }
        calculateAdaptiveThreshold()
        print("✅ Scanner ready with \(cachedUsers.count) users. Adaptive Threshold: \(adaptiveThreshold)")
    }
    
    private func calculateAdaptiveThreshold() {
        guard cachedUsers.count > 1 else { adaptiveThreshold = 0.8; return }
        var minInterUserDistance: Float = .greatestFiniteMagnitude
        for i in 0..<cachedUsers.count {
            for j in (i+1)..<cachedUsers.count {
                minInterUserDistance = min(minInterUserDistance, cachedUsers[i].embedding.euclideanDistance(to: cachedUsers[j].embedding))
            }
        }
        adaptiveThreshold = max(0.8, min(1.2, minInterUserDistance * 0.6))
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessingFrame, !isRecognitionLocked, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessingFrame = true
        let faceRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self else { return } // Fix: Safely unwrap self
            guard let results = request.results as? [VNFaceObservation] else { self.finishFrame(with: .searching); return }
            if results.count > 1 { self.finishFrame(with: .multipleFaces); return }
            guard let face = results.first else { self.finishFrame(with: .searching); return }
            self.assessFaceQuality(face: face, in: pixelBuffer)
        }
        faceRequest.revision = VNDetectFaceRectanglesRequestRevision3
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right).perform([faceRequest])
        } catch { self.finishFrame(with: .searching) }
    }
    
    private func assessFaceQuality(face: VNFaceObservation, in pixelBuffer: CVPixelBuffer) {
        let imageSize = CVImageBufferGetDisplaySize(pixelBuffer)
        let faceRect = VNImageRectForNormalizedRect(face.boundingBox, Int(imageSize.width), Int(imageSize.height))
        guard faceRect.width >= 80 && faceRect.height >= 80 else { self.finishFrame(with: .lowQuality(face, pixelBuffer)); return }
        guard face.boundingBox.minX > 0.05 && face.boundingBox.minY > 0.05 && face.boundingBox.maxX < 0.95 && face.boundingBox.maxY < 0.95 else {
            self.finishFrame(with: .lowQuality(face, pixelBuffer)); return
        }
        self.lockAndVerify(face: face, in: pixelBuffer)
    }
    
    private func lockAndVerify(face: VNFaceObservation, in pixelBuffer: CVPixelBuffer) {
        isRecognitionLocked = true
        DispatchQueue.main.async { self.delegate?.cameraService(didProduce: .verifying) }
        guard let image = CGImage.create(from: pixelBuffer) else { unlockAndFinish(with: .noMatch(face, pixelBuffer)); return }
        
        ImprovedFaceNetService.shared.generateEmbedding(from: image, for: face) { [weak self] values in
            guard let self = self, let values = values else { self?.unlockAndFinish(with: .noMatch(face, pixelBuffer)); return }
            if let user = self.verify(liveVector: FacialVector(values: values)) {
                self.unlockAndFinish(with: .match(user, face, pixelBuffer))
            } else {
                self.unlockAndFinish(with: .noMatch(face, pixelBuffer))
            }
        }
    }
    
    private func verify(liveVector: FacialVector) -> User? {
        guard !cachedUsers.isEmpty else { return nil }
        let candidates = cachedUsers.map { (user: $0.user, euclidean: liveVector.euclideanDistance(to: $0.embedding), cosine: liveVector.cosineDistance(to: $0.embedding)) }.sorted { $0.euclidean < $1.euclidean }
        guard let bestCandidate = candidates.first else { return nil }
        let passesEuclidean = bestCandidate.euclidean < adaptiveThreshold
        let passesCosine = bestCandidate.cosine < 0.4
        if passesEuclidean && passesCosine {
            print("✅ MATCH CONFIRMED (E: \(String(format: "%.4f", bestCandidate.euclidean)), C: \(String(format: "%.4f", bestCandidate.cosine)))"); return bestCandidate.user
        }
        print("--- ❌ NO MATCH (E: \(String(format: "%.4f", bestCandidate.euclidean)), C: \(String(format: "%.4f", bestCandidate.cosine)))")
        return nil
    }

    private func finishFrame(with result: ScanResult) {
        DispatchQueue.main.async { self.delegate?.cameraService(didProduce: result) }; isProcessingFrame = false
    }
    
    private func unlockAndFinish(with result: ScanResult) {
        DispatchQueue.main.async {
            self.delegate?.cameraService(didProduce: result)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.isRecognitionLocked = false }
        }
        isProcessingFrame = false
    }

    func prepare() { sessionQueue.async { if self.session.inputs.isEmpty { if !self.setupSession() { DispatchQueue.main.async { self.delegate?.cameraService(didProduce: .error("Setup Failed")) } } } } }
    private func setupSession() -> Bool { session.beginConfiguration(); defer { session.commitConfiguration() }; guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return false }; do { let input = try AVCaptureDeviceInput(device: device); if !session.canAddInput(input) { return false }; session.addInput(input) } catch { return false }; videoOutput.alwaysDiscardsLateVideoFrames = true; videoOutput.setSampleBufferDelegate(self, queue: sessionQueue); if !session.canAddOutput(videoOutput) { return false }; session.addOutput(videoOutput); session.sessionPreset = .hd1920x1080; return true }
    func startSession() { sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stopSession() { sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } } }
}
