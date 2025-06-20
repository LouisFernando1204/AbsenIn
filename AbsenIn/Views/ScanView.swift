import SwiftUI
import AVFoundation
import SwiftData

struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()
    
    @Query(sort: \User.name) private var registeredUsers: [User]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            // The CameraPreview no longer needs to pass back the layer.
            CameraPreview(session: viewModel.cameraService.session)
                .ignoresSafeArea()
            
            // THE FIX: A simple, clean overlay instead of bounding boxes.
            faceOverlay
            
            VStack {
                Text(viewModel.statusMessage)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
                    .padding(.top, 20)
                    .animation(.easeInOut, value: viewModel.statusMessage)
                
                Spacer()
            }
        }
        .onAppear {
            viewModel.activate(modelContext: modelContext, registeredUsers: Array(registeredUsers))
        }
        .onDisappear {
            viewModel.cameraService.stopSession()
        }
    }
    
    // A helper view for the new face guide overlay.
    private var faceOverlay: some View {
        Capsule()
            .stroke(viewModel.isFaceWellPositioned ? Color.green : Color.white, lineWidth: 5)
            .frame(width: 300, height: 450)
            .opacity(0.8)
            .animation(.easeInOut(duration: 0.3), value: viewModel.isFaceWellPositioned)
    }
}
