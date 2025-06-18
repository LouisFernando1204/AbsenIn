//
//  CameraView.swift
//  AbsenIn
//
//  Created by Hayya U on 17/06/25.
//

import SwiftUI
import Foundation

struct CameraView: View {
    
    // Inisialisasi camera service sebagai StateObject
    @ObservedObject var camera_service: CameraService
    
    // State untuk menyimpan gambar yang sudah diambil
    @State private var captured_image: UIImage?
    
    var body: some View {
        ZStack {
            if let image = captured_image {
                // TAMPILAN SETELAH MENGAMBIL FOTO
                VStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                    
                    Button("Ambil Ulang") {
                        captured_image = nil // Reset untuk kembali ke kamera
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
            } else {
                // Tampilan Kamera Utama
                CameraPreview(session: camera_service.session)
                    .ignoresSafeArea()
                
                // Lapisan untuk Tombol-tombol
                VStack {
                    // Tombol Ganti Kamera di Atas
                    HStack {
                        Spacer() // Mendorong tombol ke kanan
                        Button(action: {
                            // Panggil fungsi flipCamera dari service
                            camera_service.flipCamera()
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(.trailing)
                    }
                    
                    Spacer() // Mendorong tombol capture ke bawah
                    
                    // Tombol Capture di Bawah
                    Button(action: {
                        camera_service.capturePhoto()
                    }) {
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 70))
                            .foregroundColor(.white)
                    }
                    .padding(.bottom)
                }
            }
        }
        // Listener untuk menerima data foto dari CameraService
        .onReceive(camera_service.$photo_data) { data in
            if let data = data, let image = UIImage(data: data) {
                self.captured_image = image
                
                // Opsional: Simpan ke galeri
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        }
    }
}

#Preview {
    CameraView(camera_service: CameraService())
}
