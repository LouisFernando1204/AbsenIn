import Foundation
import Vision

struct FacialVector: Codable {
    let leftEyeToNose: CGFloat
    let rightEyeToNose: CGFloat
    let mouthWidthToPupilDistance: CGFloat
    let noseToMouthCenter: CGFloat
    let leftEyeToMouthCorner: CGFloat
    let rightEyeToMouthCorner: CGFloat
    let noseToChin: CGFloat
    let eyeToEyebrow: CGFloat
    let jawWidthToPupilDistance: CGFloat
    let mouthToChin: CGFloat

    func distance(to other: FacialVector) -> CGFloat {
        let errors = [
            abs(self.leftEyeToNose - other.leftEyeToNose),
            abs(self.rightEyeToNose - other.rightEyeToNose),
            abs(self.mouthWidthToPupilDistance - other.mouthWidthToPupilDistance),
            abs(self.noseToMouthCenter - other.noseToMouthCenter),
            abs(self.leftEyeToMouthCorner - other.leftEyeToMouthCorner),
            abs(self.rightEyeToMouthCorner - other.rightEyeToMouthCorner),
            abs(self.noseToChin - other.noseToChin),
            abs(self.eyeToEyebrow - other.eyeToEyebrow),
            abs(self.jawWidthToPupilDistance - other.jawWidthToPupilDistance),
            abs(self.mouthToChin - other.mouthToChin)
        ]
        return errors.reduce(0, +) / CGFloat(errors.count)
    }
}

extension VNFaceLandmarks2D {
    func toFacialVector() -> FacialVector? {
        func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
            return hypot(p2.x - p1.x, p2.y - p1.y)
        }

        guard let leftPupil = self.leftPupil?.normalizedPoints.first,
              let rightPupil = self.rightPupil?.normalizedPoints.first,
              let nose = self.nose?.normalizedPoints.first,
              let leftMouth = self.outerLips?.normalizedPoints.first,
              let rightMouth = self.outerLips?.normalizedPoints.last,
              let faceContourPoints = self.faceContour?.normalizedPoints,
              let chinPoint = faceContourPoints.min(by: { $0.y < $1.y }),
              let leftEyebrow = self.leftEyebrow?.normalizedPoints.first,
              let rightEyebrow = self.rightEyebrow?.normalizedPoints.first,
              let leftJaw = faceContourPoints.first,
              let rightJaw = faceContourPoints.last
        else { return nil }

        let pupilDistance = distance(leftPupil, rightPupil)
        guard pupilDistance > 0 else { return nil }
        
        let mouthCenter = CGPoint(x: (leftMouth.x + rightMouth.x) / 2, y: (leftMouth.y + rightMouth.y) / 2)
        let avgEyebrowToEyeDist = (distance(leftPupil, leftEyebrow) + distance(rightPupil, rightEyebrow)) / 2

        return FacialVector(
            leftEyeToNose: distance(leftPupil, nose) / pupilDistance,
            rightEyeToNose: distance(rightPupil, nose) / pupilDistance,
            mouthWidthToPupilDistance: distance(leftMouth, rightMouth) / pupilDistance,
            noseToMouthCenter: distance(nose, mouthCenter) / pupilDistance,
            leftEyeToMouthCorner: distance(leftPupil, leftMouth) / pupilDistance,
            rightEyeToMouthCorner: distance(rightPupil, rightMouth) / pupilDistance,
            noseToChin: distance(nose, chinPoint) / pupilDistance,
            eyeToEyebrow: avgEyebrowToEyeDist / pupilDistance,
            jawWidthToPupilDistance: distance(leftJaw, rightJaw) / pupilDistance,
            mouthToChin: distance(mouthCenter, chinPoint) / pupilDistance
        )
    }
}
