// ScanView.swift (GANTI SELURUH FILE)

import SwiftUI
import AVFoundation
import SwiftData

struct ScanView: View {
    @StateObject private var viewModel = ScanViewModel()
    
    @Query(sort: \User.name) private var registeredUsers: [User]
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        ZStack {
            CameraPreview(
                session: viewModel.cameraService.session,
                videoDevice: viewModel.cameraService.videoDevice
            )
            .ignoresSafeArea()
            
            // Overlay pemandu wajah yang lebih baik
            faceOverlay
            
            VStack {
                statusMessageView
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
    
    // View untuk overlay pemandu wajah
    private var faceOverlay: some View {
        Circle()
            .stroke(viewModel.isFaceDetected ? Color.green : Color.white, lineWidth: 5)
            .frame(width: 300, height: 300)
            .opacity(0.8)
            .animation(.easeInOut(duration: 0.3), value: viewModel.isFaceDetected)
    }
    
    // View untuk pesan status
    private var statusMessageView: some View {
        Text(viewModel.statusMessage)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
            .padding(.top, 60)
            .animation(.easeInOut, value: viewModel.statusMessage)
    }
}
