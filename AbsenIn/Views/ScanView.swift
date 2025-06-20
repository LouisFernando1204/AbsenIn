import SwiftUI
import AVFoundation
import SwiftData

struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()
    
    @Query(sort: \User.name) private var registeredUsers: [User]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.cameraService.session)
                .ignoresSafeArea()
            
            // PERBAIKAN UI: Menghapus bounding box dan menggunakan overlay lingkaran.
            faceOverlay
            
            VStack {
                Text(viewModel.statusMessage)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
                    .padding(.top, 40)
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
    
    // Helper view untuk overlay pemandu wajah yang bersih.
    private var faceOverlay: some View {
        Circle()
            .stroke(viewModel.isFaceWellPositioned ? Color.green : Color.white, lineWidth: 5)
            .frame(width: 300, height: 300)
            .opacity(0.8)
            .animation(.easeInOut(duration: 0.3), value: viewModel.isFaceWellPositioned)
    }
}
