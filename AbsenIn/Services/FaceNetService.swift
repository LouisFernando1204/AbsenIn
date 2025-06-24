//import Vision
//import UIKit
//import Accelerate
//
//extension CGImage {
//    func resized(to size: CGSize) -> CGImage? {
//        guard var format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue), renderingIntent: .defaultIntent) else { return nil }
//        var sourceBuffer = vImage_Buffer(); defer { sourceBuffer.data.deallocate() }
//        var error = vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, self, vImage_Flags(kvImageNoFlags))
//        guard error == kvImageNoError else { return nil }
//        let scale = min(size.width / CGFloat(width), size.height / CGFloat(height))
//        let destWidth = Int(CGFloat(width) * scale); let destHeight = Int(CGFloat(height) * scale)
//        var destBuffer = vImage_Buffer(); error = vImageBuffer_Init(&destBuffer, UInt(destHeight), UInt(destWidth), format.bitsPerComponent, vImage_Flags(kvImageNoFlags))
//        guard error == kvImageNoError else { return nil }; defer { destBuffer.data.deallocate() }
//        error = vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
//        guard error == kvImageNoError else { return nil }
//        return try? destBuffer.createCGImage(format: format)
//    }
//}
//
//extension MLMultiArray {
//    func toFloatArray() -> [Float] {
//        let count = self.count; let pointer = self.dataPointer.bindMemory(to: Float.self, capacity: count); return Array(UnsafeBufferPointer(start: pointer, count: count))
//    }
//}
//
//
//class FaceNetService {
//    static let shared = FaceNetService()
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
//            guard let multiArray = self.preprocess(image: fullImage, observation: faceObservation) else {
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
//    private func preprocess(image: CGImage, observation: VNFaceObservation) -> MLMultiArray? {
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
