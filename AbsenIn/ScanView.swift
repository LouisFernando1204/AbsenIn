//
//  ScanView.swift
//  AbsenIn
//
//  Created by Louis Fernando on 18/06/25.
//

import SwiftUI
import AVFoundation
import SwiftData

struct ScanView: View {
    @StateObject private var viewModel: ScanViewModel
    
    @Query(sort: \User.name) private var registeredUsers: [User]
    @Environment(\.modelContext) private var modelContext
    
    init() {
        _viewModel = StateObject(wrappedValue: ScanViewModel())
    }
    
    var body: some View {
        ZStack {
            // Ini sekarang dengan jelas memanggil struct dari file CameraPreview.swift
            CameraPreview(session: viewModel.cameraService.session)
                .ignoresSafeArea()
            
            GeometryReader { geometry in
                ForEach(viewModel.detectedFaces) { face in
                    let rect = viewModel.convertRect(for: face.boundingBox, in: geometry.size)
                    
                    Path(rect)
                        .stroke(face.color, lineWidth: 2)
                    
                    Text(face.name ?? "Tidak Dikenali")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(face.color)
                        .cornerRadius(4)
                        .position(x: rect.midX, y: rect.minY - 15)
                }
            }
            
            VStack {
                Spacer()
                Text(viewModel.statusMessage)
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
                    .padding(.bottom, 30)
                    .opacity(viewModel.statusMessage.isEmpty ? 0 : 1)
                    .animation(.easeInOut, value: viewModel.statusMessage)
            }
        }
        .onAppear {
            viewModel.setup(modelContext: modelContext, registeredUsers: Array(registeredUsers))
            viewModel.cameraService.startSession()
        }
        .onDisappear {
            viewModel.cameraService.stopSession()
        }
    }
}
