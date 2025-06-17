//
//  RegistrationView.swift
//  AbsenIn
//
//  Created by Louis Fernando on 17/06/25.
//

import SwiftUI
import Vision
import CoreImage

struct RegistrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State Properties
    @State private var capturedImage: UIImage?
    @State private var userName: String = ""
    @State private var isProcessing = false // Untuk loading screen di akhir
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    // State untuk alur pendaftaran 3 langkah
    @State private var registrationStep = 0
    @State private var collectedFeaturePrints: [VNFeaturePrintObservation] = []
    
    private let cameraService = CameraService()
    
    private let registrationInstructions = [
        "Posisikan wajah Anda dan toleh sedikit ke KIRI",
        "Sekarang, lihat LURUS ke kamera",
        "Terakhir, toleh sedikit ke KANAN"
    ]

    var body: some View {
        VStack {
            if isProcessing {
                ProgressView("Menyelesaikan pendaftaran...")
                    .scaleEffect(1.5)
            } else {
                VStack {
                    // --- PERBAIKAN DI SINI ---
                    // Tambahkan pengecekan untuk mencegah 'Index out of range'
                    if registrationStep < registrationInstructions.count {
                        Text(registrationInstructions[registrationStep])
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    
                    ZStack(alignment: .bottom) {
                        CameraView(capturedImage: $capturedImage, cameraService: cameraService)
                            .frame(height: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .padding(.horizontal)
                        
                        // Overlay progres
                        HStack(spacing: 15) {
                            ForEach(0..<3) { index in
                                Circle()
                                    .fill(index < registrationStep ? Color.green : Color.gray.opacity(0.5))
                                    .frame(width: 15, height: 15)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    
                    if registrationStep == 0 {
                        TextField("Masukkan Nama Anda", text: $userName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding()
                    }
                    
                    // Tombol ini tidak akan terlihat jika registrationStep >= 3,
                    // karena seluruh VStack ini akan digantikan oleh ProgressView
                    Button("Ambil Gambar Posisi Ini") {
                        cameraService.capturePhoto()
                    }
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isRegistrationButtonEnabled() ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding()
                    .disabled(!isRegistrationButtonEnabled())
                }
            }
        }
        .animation(.default, value: isProcessing)
        .animation(.default, value: registrationStep)
        .onChange(of: capturedImage) { _, newImage in
            if let image = newImage {
                processCapturedImage(image)
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Pendaftaran"), message: Text(alertMessage), dismissButton: .default(Text("OK")) {
                if alertMessage.contains("berhasil") {
                    dismiss()
                }
            })
        }
        .navigationTitle("Pendaftaran Wajah")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // ... sisa fungsi lainnya tetap sama persis ...
    
    private func isRegistrationButtonEnabled() -> Bool {
        // Tombol hanya aktif jika nama sudah diisi di langkah pertama
        if registrationStep == 0 {
            return !userName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    private func processCapturedImage(_ image: UIImage) {
        // Proses di background thread
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = image.cgImage else { return }

            let faceDetectionRequest = VNDetectFaceRectanglesRequest { (request, error) in
                guard let faceObservation = request.results?.first as? VNFaceObservation else {
                    showError(message: "Wajah tidak terdeteksi. Mohon coba lagi.")
                    return
                }

                let originalImage = CIImage(cgImage: cgImage)
                let boundingBox = faceObservation.boundingBox
                let faceImageRect = VNImageRectForNormalizedRect(boundingBox, Int(originalImage.extent.width), Int(originalImage.extent.height))
                let croppedFaceImage = originalImage.cropped(to: faceImageRect)
                
                let featureprintRequest = VNGenerateImageFeaturePrintRequest()
                let handler = VNImageRequestHandler(ciImage: croppedFaceImage, options: [:])
                
                do {
                    try handler.perform([featureprintRequest])
                    guard let featurePrint = featureprintRequest.results?.first as? VNFeaturePrintObservation else {
                        showError(message: "Gagal membuat sidik jari wajah.")
                        return
                    }

                    // Kumpulkan hasil dan lanjut ke langkah berikutnya
                    DispatchQueue.main.async {
                        self.collectedFeaturePrints.append(featurePrint)
                        self.registrationStep += 1
                        
                        // Jika semua langkah selesai, finalisasi
                        if self.registrationStep >= 3 {
                            self.finalizeRegistration()
                        }
                    }
                } catch {
                    showError(message: "Terjadi kesalahan analisis: \(error.localizedDescription)")
                }
            }
            
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([faceDetectionRequest])
        }
    }

    private func finalizeRegistration() {
        // Tampilkan loading screen
        isProcessing = true
        
        // Pastikan kita punya 3 feature print
        guard collectedFeaturePrints.count == 3 else {
            showError(message: "Data pendaftaran tidak lengkap.")
            return
        }
        
        let highQualityFeaturePrint = collectedFeaturePrints[1] // Index 1 adalah posisi tengah
        
        saveUser(featurePrint: highQualityFeaturePrint)
    }
    
    private func saveUser(featurePrint: VNFeaturePrintObservation) {
        do {
            let featureprintData = try NSKeyedArchiver.archivedData(withRootObject: featurePrint, requiringSecureCoding: true)
            let newUser = User(name: userName, faceprintData: featureprintData)
            
            DispatchQueue.main.async {
                modelContext.insert(newUser)
                try? modelContext.save()
                
                self.alertMessage = "Pendaftaran wajah untuk \(userName) berhasil!"
                self.showAlert = true
                self.isProcessing = false
            }
        } catch {
            showError(message: "Gagal menyimpan data wajah: \(error.localizedDescription)")
        }
    }
    
    private func showError(message: String) {
        DispatchQueue.main.async {
            self.alertMessage = message
            self.showAlert = true
            self.isProcessing = false
        }
    }
}
