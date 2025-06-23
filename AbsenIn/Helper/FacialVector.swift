import Foundation
import Vision

// FacialVector sekarang menyimpan vektor geometris dari semua 76 landmark.
struct FacialVector: Codable {
    let vector: [Float]

    func euclideanDistance(to other: FacialVector) -> Float {
        guard self.vector.count == other.vector.count else {
            return .greatestFiniteMagnitude
        }
        
        var sumOfSquaredDifferences: Float = 0.0
        
        for i in 0..<self.vector.count {
            let difference = self.vector[i] - other.vector[i]
            sumOfSquaredDifferences += difference * difference
        }
        
        return sqrt(sumOfSquaredDifferences)
    }
}

// Ekstensi untuk mengubah SEMUA 76 titik landmark menjadi satu vektor.
extension VNFaceLandmarks2D {
    func toFacialVector() -> FacialVector? {
        // Kumpulkan semua titik dari semua fitur wajah yang tersedia.
        let allPoints = [
            self.faceContour,
            self.leftEyebrow,
            self.rightEyebrow,
            self.leftEye,
            self.rightEye,
            self.leftPupil,
            self.rightPupil,
            self.nose,
            self.noseCrest,
            self.medianLine,
            self.outerLips,
            self.innerLips
        ]
        .compactMap { $0 } // Hapus fitur yang mungkin tidak terdeteksi (nil)
        .flatMap { $0.normalizedPoints } // Gabungkan semua titik menjadi satu array CGPoint
        
        // Pastikan kita memiliki cukup titik untuk dianggap valid.
        guard !allPoints.isEmpty else { return nil }
        
        // "Flatten" array dari CGPoint menjadi satu array [Float].
        let floatVector = allPoints.flatMap { [Float($0.x), Float($0.y)] }
        
        return FacialVector(vector: floatVector)
    }
}
