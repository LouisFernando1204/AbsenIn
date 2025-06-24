import SwiftUI
import Vision

// REWRITTEN: A correct and reusable view for displaying Vision bounding boxes.
struct BoundingBoxView: View {
    var faceObservation: VNFaceObservation?
    var isMatch: Bool
    
    var body: some View {
        GeometryReader { geometry in
            if let observation = faceObservation {
                // Ensure the observation has valid dimensions to avoid drawing a zero-size rect
                if observation.boundingBox.width > 0, observation.boundingBox.height > 0 {
                    let previewRect = geometry.frame(in: .local)
                    
                    // This function handles the coordinate system transformation
                    let transformedRect = transformedBoundingBox(observation.boundingBox, in: previewRect)
                    
                    Rectangle()
                        .stroke(isMatch ? Color.green : Color.yellow, lineWidth: 3)
                        .frame(width: transformedRect.width, height: transformedRect.height)
                        .position(x: transformedRect.midX, y: transformedRect.midY)
                        .animation(.easeInOut, value: isMatch)
                        .animation(.easeInOut, value: transformedRect)
                }
            }
        }
    }
    
    /// Converts Vision's normalized, bottom-left-origin bounding box to SwiftUI's top-left-origin coordinate system.
    private func transformedBoundingBox(_ normalizedRect: CGRect, in previewRect: CGRect) -> CGRect {
        // 1. Create a transform to flip the Y-coordinate. Vision's origin is bottom-left, SwiftUI's is top-left.
        let transform = CGAffineTransform(scaleX: 1, y: -1)
            .translatedBy(x: 0, y: -previewRect.height)
        
        // 2. Create a transform to scale the normalized (0-1) rect to the screen size.
        let scale = CGAffineTransform.identity.scaledBy(x: previewRect.width, y: previewRect.height)
        
        // 3. Apply the scaling first, then the flipping transform to get the final rect.
        return normalizedRect.applying(scale).applying(transform)
    }
}
