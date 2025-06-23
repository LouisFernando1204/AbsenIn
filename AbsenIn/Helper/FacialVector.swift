// FacialVector.swift (atau file ekstensi Anda)

import Foundation
import Vision

// Struct ini tidak berubah
struct FacialVector: Codable {
    let values: [Float]
    
    func euclideanDistance(to other: FacialVector) -> Float {
        guard values.count == other.values.count else { return .greatestFiniteMagnitude }
        
        let sumOfSquaredDifferences = zip(values, other.values)
            .map { $0 - $1 }
            .map { $0 * $0 }
            .reduce(0, +)
        
        return sqrt(sumOfSquaredDifferences)
    }
}

// PERBAIKAN UTAMA FINAL: Ganti ekstensi VNFaceLandmarks2D Anda dengan yang ini
extension VNFaceLandmarks2D {
    
    func toFacialVector() -> FacialVector? {
        // 1. Gunakan fitur internal yang stabil.
        let allPoints = [
            self.leftEye, self.rightEye,
            self.leftEyebrow, self.rightEyebrow, self.nose,
            self.noseCrest, self.medianLine, self.outerLips, self.innerLips
        ].compactMap { $0?.normalizedPoints }.flatMap { $0 }
        
        guard !allPoints.isEmpty else { return nil }
        
        // 2. Lakukan normalisasi kustom PADA TITIK YANG SUDAH DINORMALISASI VISION.
        // Ini membuat vektor kebal terhadap posisi, ukuran, DAN rasio aspek bounding box.
        guard let leftPupil = self.leftPupil?.normalizedPoints.first,
              let rightPupil = self.rightPupil?.normalizedPoints.first else {
            return nil // Butuh mata untuk normalisasi
        }
        
        // Titik pusat yang stabil
        let centerPoint = CGPoint(x: (leftPupil.x + rightPupil.x) / 2,
                                  y: (leftPupil.y + rightPupil.y) / 2)
        
        // Skala yang stabil (jarak antar mata)
        let interocularDistance = hypot(leftPupil.x - rightPupil.x, leftPupil.y - rightPupil.y)
        guard interocularDistance > 0 else { return nil }
        
        // 3. Normalisasi setiap titik terhadap pusat dan skala yang baru.
        let normalizedPoints = allPoints.map { point -> (Float, Float) in
            let translatedX = Float(point.x - centerPoint.x) / Float(interocularDistance)
            let translatedY = Float(point.y - centerPoint.y) / Float(interocularDistance)
            return (translatedX, translatedY)
        }
        
        // 4. Ratakan (flatten) menjadi satu array.
        let finalVectorValues = normalizedPoints.flatMap { [$0.0, $0.1] }
        
        return FacialVector(values: finalVectorValues)
    }
}
