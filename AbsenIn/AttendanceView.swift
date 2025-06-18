//
//  AttendanceView.swift
//  AbsenIn
//
//  Created by Louis Fernando on 17/06/25.
//

import SwiftUI
import SwiftData
import AVFoundation

struct AttendanceView: View {
    @StateObject private var coordinator: AttendanceCoordinator
    private let cameraService = RealtimeCameraService()

    private let users: [User]

    init(users: [User], modelContext: ModelContext) {
        self.users = users // Simpan users
        // Inisialisasi StateObject di init dengan parameter yang benar
        _coordinator = StateObject(wrappedValue: AttendanceCoordinator(modelContext: modelContext))
    }
    
    var body: some View {
        VStack {
            ZStack(alignment: .bottom) {
                CameraPreview(cameraService: cameraService)
                    .ignoresSafeArea()
                
                // Baca status dari coordinator, bukan dari @State lokal lagi
                Text(coordinator.recognitionStatus)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding()
                    .background(coordinator.statusColor.opacity(0.7))
                    .cornerRadius(10)
                    .padding(.bottom, 50)
            }
        }
        .onAppear {
            // Setup koneksi di onAppear
            // Ini cara 'hacky', cara yang lebih baik adalah menggunakan View yang berbeda
            // Namun untuk saat ini, kita bisa set ulang propertinya
            // Sebenarnya, karena coordinator adalah class, kita bisa langsung set propertinya.
            // Tapi untuk amannya, kita akan set delegate di sini.
            
            // Beri tahu camera service bahwa delegate-nya adalah coordinator
            cameraService.delegate = coordinator
            cameraService.startSession(registeredUsers: users)
        }
        .onDisappear {
            cameraService.stopSession()
        }
    }
}

// Hapus extension AttendanceView: FaceRecognitionDelegate dari sini.
// extension AttendanceView: FaceRecognitionDelegate { ... } // << HAPUS BAGIAN INI

// Wrapper SwiftUI untuk AVCaptureVideoPreviewLayer (tetap sama)
// Wrapper SwiftUI untuk AVCaptureVideoPreviewLayer yang sudah diperbaiki
struct CameraPreview: UIViewRepresentable {
    // Terima service untuk mendapatkan session-nya
    let cameraService: RealtimeCameraService

    func makeUIView(context: Context) -> VideoPreviewUIView {
        // Buat view kustom kita dan berikan session dari service
        return VideoPreviewUIView(session: cameraService.session)
    }
    
    func updateUIView(_ uiView: VideoPreviewUIView, context: Context) {}
}

// UIView kustom yang tahu cara menampilkan dan me-layout layer kamera
class VideoPreviewUIView: UIView {
    
    private var previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        // Buat preview layer saat view diinisialisasi
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero) // Frame awal akan diatur oleh SwiftUI
        
        // Atur properti layer
        previewLayer.videoGravity = .resizeAspectFill
        
        // Tambahkan layer sebagai sublayer dari view ini
        self.layer.addSublayer(previewLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // INI BAGIAN KUNCINYA!
    // Metode ini akan dipanggil setiap kali view perlu menata ulang layout-nya.
    override func layoutSubviews() {
        super.layoutSubviews()
        // Atur frame dari previewLayer agar sama persis dengan bounds dari view ini.
        previewLayer.frame = self.bounds
    }
}
