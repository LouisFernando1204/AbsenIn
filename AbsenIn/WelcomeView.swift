//
//  WelcomeView.swift
//  AbsenIn
//
//  Created by Louis Fernando on 17/06/25.
//

import SwiftUI
import AVFoundation

struct WelcomeView: View {
    // State untuk mengontrol alur ke layar pendaftaran
    @State private var navigateToRegistration = false
    // State untuk menampilkan pesan error jika izin ditolak
    @State private var showingPermissionError = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Selamat Datang di Aplikasi Presensi Wajah")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Aplikasi ini akan menggunakan kamera untuk mengenali wajah Anda saat presensi. Data wajah Anda disimpan secara aman dan lokal di perangkat ini.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Mulai Pendaftaran") {
                    requestCameraPermission()
                }
                .font(.headline)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
            .navigationDestination(isPresented: $navigateToRegistration) {
                // Arahkan ke RegistrationView saat navigateToRegistration = true
                RegistrationView()
            }
            .alert("Izin Kamera Dibutuhkan", isPresented: $showingPermissionError) {
                Button("OK") {}
            } message: {
                Text("Mohon berikan izin akses kamera di Pengaturan untuk melanjutkan.")
            }
        }
    }
    
    // Fungsi untuk meminta izin kamera
    private func requestCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: // Izin sudah diberikan
            self.navigateToRegistration = true
        case .notDetermined: // Izin belum ditanya
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.navigateToRegistration = true
                    } else {
                        self.showingPermissionError = true
                    }
                }
            }
        case .denied, .restricted: // Izin ditolak atau dibatasi
            self.showingPermissionError = true
        @unknown default:
            break
        }
    }
}
