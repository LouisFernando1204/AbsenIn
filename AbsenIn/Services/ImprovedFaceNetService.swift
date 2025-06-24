//import Vision
//import UIKit
//import Accelerate
//
//// This service contains the L2 normalization, padding, and configurable preprocessing.
//class ImprovedFaceNetService {
//    static let shared = ImprovedFaceNetService()
//    private var coreMLModel: FaceNetModel?
//    
//    // The normalization type is now explicit. .minusOneToOne is correct for your model.
//    private enum NormalizationType {
//        case minusOneToOne
//    }
//    private let normalizationType: NormalizationType = .minusOneToOne
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
//            print("❌ Model not loaded"); completion(nil); return
//        }
//        
//        DispatchQueue.global(qos: .userInitiated).async {
//            guard let multiArray = self.improvedPreprocess(image: fullImage, observation: faceObservation) else {
//                DispatchQueue.main.async { completion(nil) }; return
//            }
//            
//            do {
//                let input = FaceNetModelInput(input: multiArray)
//                let predictionOutput = try model.prediction(input: input)
//                let embedding = predictionOutput.embeddings.toFloatArray()
//                
//                // CRITICAL IMPROVEMENT: L2 normalization of the final embedding vector.
//                let normalizedEmbedding = self.l2Normalize(embedding)
//                
//                DispatchQueue.main.async { completion(normalizedEmbedding) }
//            } catch {
//                print("❌ Prediction failed: \(error)"); DispatchQueue.main.async { completion(nil) }
//            }
//        }
//    }
//    
//    private func improvedPreprocess(image: CGImage, observation: VNFaceObservation) -> MLMultiArray? {
//        let targetSize = 160
//        
//        // Add padding to the face crop to give the model more context.
//        let paddingRatio: CGFloat = 0.20
//        var paddedBoundingBox = observation.boundingBox
//        let horizontalPadding = paddedBoundingBox.width * paddingRatio
//        let verticalPadding = paddedBoundingBox.height * paddingRatio
//        paddedBoundingBox.origin.x -= horizontalPadding / 2
//        paddedBoundingBox.origin.y -= verticalPadding / 2
//        paddedBoundingBox.size.width += horizontalPadding
//        paddedBoundingBox.size.height += verticalPadding
//        
//        // Ensure the padded box does not go outside the image boundaries.
//        let clampedBoundingBox = paddedBoundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
//        
//        let imageRect = VNImageRectForNormalizedRect(clampedBoundingBox, image.width, image.height)
//        guard let croppedImage = image.cropping(to: imageRect) else { return nil }
//        guard let resizedImage = croppedImage.resized(to: CGSize(width: targetSize, height: targetSize)) else { return nil }
//        
//        return normalizeAndConvertToMultiArray(image: resizedImage)
//    }
//    
//    private func normalizeAndConvertToMultiArray(image: CGImage) -> MLMultiArray? {
//        let targetSize = 160
//        do {
//            let multiArray = try MLMultiArray(shape: [1, NSNumber(value: targetSize), NSNumber(value: targetSize), 3], dataType: .float32)
//            var pixelBuffer: CVPixelBuffer?
//            let status = CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
//            guard status == kCVReturnSuccess, let finalPixelBuffer = pixelBuffer else { return nil }
//            CVPixelBufferLockBaseAddress(finalPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
//            let pixelData = CVPixelBufferGetBaseAddress(finalPixelBuffer)
//            let context = CGContext(data: pixelData, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(finalPixelBuffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
//            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
//            CVPixelBufferLockBaseAddress(finalPixelBuffer, .readOnly); defer { CVPixelBufferUnlockBaseAddress(finalPixelBuffer, .readOnly) }
//            guard let baseAddress = CVPixelBufferGetBaseAddress(finalPixelBuffer) else { return nil }
//            let byteBuffer = baseAddress.assumingMemoryBound(to: UInt8.self)
//            for i in 0..<(targetSize * targetSize) {
//                let pixelIndex = i * 4
//                let rawR = Float(byteBuffer[pixelIndex + 2])
//                let rawG = Float(byteBuffer[pixelIndex + 1])
//                let rawB = Float(byteBuffer[pixelIndex + 0])
//                let (r, g, b) = normalizePixel(r: rawR, g: rawG, b: rawB)
//                let y = i / targetSize
//                let x = i % targetSize
//                multiArray[[0, y as NSNumber, x as NSNumber, 0]] = NSNumber(value: r)
//                multiArray[[0, y as NSNumber, x as NSNumber, 1]] = NSNumber(value: g)
//                multiArray[[0, y as NSNumber, x as NSNumber, 2]] = NSNumber(value: b)
//            }
//            CVPixelBufferUnlockBaseAddress(finalPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
//            return multiArray
//        } catch {
//            print("❌ Error creating MLMultiArray: \(error)"); return nil
//        }
//    }
//    
//    private func normalizePixel(r: Float, g: Float, b: Float) -> (Float, Float, Float) {
//        switch normalizationType {
//        case .minusOneToOne:
//            return ((r / 255.0 - 0.5) * 2.0, (g / 255.0 - 0.5) * 2.0, (b / 255.0 - 0.5) * 2.0)
//        }
//    }
//    
//    private func l2Normalize(_ embedding: [Float]) -> [Float] {
//        let magnitude = sqrt(embedding.map { $0 * $0 }.reduce(0, +))
//        guard magnitude > 0 else { return embedding }
//        return embedding.map { $0 / magnitude }
//    }
//}
