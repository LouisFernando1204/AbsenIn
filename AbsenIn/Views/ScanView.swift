import SwiftUI
import SwiftData
import Vision

struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()
    @Query(sort: \User.name) private var registeredUsers: [User]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.cameraService.session)
                .ignoresSafeArea()
            
            // --- THIS IS THE UI FIX ---
            // Add the horizontal flip to match the mirrored camera preview.
            // This will make the bounding box track your face correctly.
            BoundingBoxView(
                faceObservation: viewModel.faceObservation,
                isMatch: viewModel.isMatch
            )
            .scaleEffect(x: -1, y: 1, anchor: .center)
            // --- END FIX ---
            
            VStack {
                Text(viewModel.statusMessage)
                    .fontWeight(.semibold).foregroundColor(.white).padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color.black.opacity(0.6)).clipShape(Capsule()).padding(.top, 60)
                    .animation(.easeInOut, value: viewModel.statusMessage)
                Spacer()
            }
        }
        .onAppear { viewModel.activate(modelContext: modelContext, registeredUsers: Array(registeredUsers)) }
        .onDisappear { viewModel.deactivate() }
        .onChange(of: registeredUsers) {
             viewModel.cameraService.updateRegisteredUsers(Array(registeredUsers))
        }
    }
}
