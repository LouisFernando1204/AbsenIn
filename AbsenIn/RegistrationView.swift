//
//  RegistrationView.swift
//  AbsenIn
//
//  Created by Louis Fernando on 17/06/25.
//

import SwiftUI
import Vision
import CoreImage
import SwiftData

struct RegistrationView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \User.name) private var users: [User]
    
    @State private var isShowingRegistrationSheet = false
    
    var body: some View {
        VStack {
            if users.isEmpty {
                ContentUnavailableView(
                    "Belum Ada Pengguna",
                    systemImage: "person.3.sequence",
                    description: Text("Silakan daftarkan pengguna pertama dengan menekan tombol di bawah.")
                )
            } else {
                List {
                    ForEach(users) { user in
                        Text(user.name)
                    }
                    .onDelete(perform: deleteUser)
                }
            }
        }
        .navigationTitle("Pengguna Terdaftar")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarLeading) {
                if !users.isEmpty {
                    EditButton()
                }
            }
            
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button(action: { isShowingRegistrationSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $isShowingRegistrationSheet) {
            FaceRegistrationSheet()
        }
    }
    
    private func deleteUser(at offsets: IndexSet) {
        for index in offsets {
            let userToDelete = users[index]
            modelContext.delete(userToDelete)
        }
    }
}

// View terpisah untuk proses pendaftaran dalam sheet
struct FaceRegistrationSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var photoService = PhotoCaptureService()
    
    // State untuk alur multi-langkah
    @State private var registrationStep = 0
    @State private var collectedFeaturePrints: [VNFeaturePrintObservation] = []
    
    // PERBAIKAN: State untuk mengelola 5 jepretan per pose
    @State private var captureCount = 0
    private let capturesPerPose = 5
    @State private var multiCaptureStatusMessage = ""
    
    private let registrationSteps: [(prompt: String, systemImage: String)] = [
        ("Lihat Lurus ke Depan", "arrow.up.message"),
        ("Toleh Sedikit ke Kanan", "arrow.right"),
        ("Toleh Sedikit ke Kiri", "arrow.left"),
        ("Sedikit Menunduk", "arrow.down")
    ]
    
    @State private var userName: String = ""
    @State private var isProcessing = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var registrationSuccess = false
    
    var body: some View {
        NavigationStack {
            VStack {
                // Tampilkan status proses yang lebih detail
                if isProcessing {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(multiCaptureStatusMessage)
                            .padding(.top)
                            .foregroundColor(.secondary)
                    }
                } else {
                    if registrationStep < registrationSteps.count {
                        let currentStep = registrationSteps[registrationStep]
                        VStack {
                            Image(systemName: currentStep.systemImage)
                                .font(.system(size: 50))
                                .foregroundColor(.accentColor)
                            Text(currentStep.prompt)
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.top, 8)
                        }
                        .padding()
                    }
                    
                    ZStack(alignment: .bottom) {
                        PhotoCaptureView(service: photoService)
                            .frame(height: 350)
                            .clipShape(Circle())
                            .padding(.horizontal)
                        
                        HStack(spacing: 10) {
                            ForEach(0..<registrationSteps.count, id: \.self) { index in
                                Circle()
                                    .fill(index < registrationStep ? Color.green : Color.gray.opacity(0.5))
                                    .frame(width: 12, height: 12)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    
                    if registrationStep == 0 {
                        TextField("Masukkan Nama Lengkap", text: $userName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding()
                    }
                    
                    Button("Mulai Ambil Gambar Posisi Ini") {
                        // PERBAIKAN: Panggil fungsi untuk memulai multi-capture
                        startMultiCapture()
                    }
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isButtonEnabled() ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding()
                    .disabled(!isButtonEnabled())
                }
            }
            .animation(.default, value: isProcessing)
            .animation(.default, value: registrationStep)
            .onAppear { photoService.startRunning() }
            .onDisappear { photoService.stopRunning() }
            .alert("Status Pendaftaran", isPresented: $showAlert) {
                Button("OK") {
                    if registrationSuccess {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .navigationTitle("Pendaftaran Wajah")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Batal") { dismiss() }
                }
            }
        }
    }
    
    private func isButtonEnabled() -> Bool {
        return !isProcessing && (registrationStep > 0 || !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    
    // PERBAIKAN: Fungsi baru untuk memulai proses 5 jepretan
    private func startMultiCapture() {
        isProcessing = true
        captureCount = 0
        captureSingleImageForMultiShot()
    }
    
    // PERBAIKAN: Fungsi yang mengambil satu gambar dan memanggil dirinya lagi jika perlu
    private func captureSingleImageForMultiShot() {
        captureCount += 1
        multiCaptureStatusMessage = "Mengambil gambar \(captureCount) dari \(capturesPerPose)..."
        
        // Beri jeda singkat agar kamera stabil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            photoService.capturePhoto { capturedImage in
                guard let image = capturedImage, let cgImage = image.cgImage else {
                    showError(message: "Gagal mengambil gambar. Coba lagi.")
                    return
                }
                
                let faceDetectionRequest = VNDetectFaceLandmarksRequest { (request, error) in
                    guard let faceObservation = request.results?.first as? VNFaceObservation else {
                        showError(message: "Wajah tidak terdeteksi di jepretan \(captureCount). Posisikan wajah dengan jelas.")
                        return
                    }
                    
                    let featureprintRequest = VNGenerateImageFeaturePrintRequest()
                    featureprintRequest.regionOfInterest = faceObservation.boundingBox
                    
                    do {
                        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                        try handler.perform([featureprintRequest])
                        
                        guard let featurePrint = featureprintRequest.results?.first as? VNFeaturePrintObservation else {
                            showError(message: "Gagal membuat sidik jari wajah.")
                            return
                        }
                        
                        // Kumpulkan feature print
                        self.collectedFeaturePrints.append(featurePrint)
                        
                        // Cek apakah masih perlu mengambil gambar lagi untuk pose ini
                        if self.captureCount < self.capturesPerPose {
                            // Panggil lagi untuk jepretan berikutnya
                            self.captureSingleImageForMultiShot()
                        } else {
                            // Selesai untuk pose ini, lanjut ke pose berikutnya
                            DispatchQueue.main.async {
                                self.registrationStep += 1
                                self.isProcessing = false
                                
                                // Jika semua pose selesai, finalisasi
                                if self.registrationStep >= self.registrationSteps.count {
                                    self.finalizeRegistration()
                                }
                            }
                        }
                        
                    } catch {
                        showError(message: "Terjadi kesalahan analisis: \(error.localizedDescription)")
                    }
                }
                
                do {
                    try VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:]).perform([faceDetectionRequest])
                } catch {
                    showError(message: "Gagal memproses gambar: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func finalizeRegistration() {
        isProcessing = true
        multiCaptureStatusMessage = "Menyimpan data wajah..."
        
        guard !collectedFeaturePrints.isEmpty else {
            showError(message: "Data pendaftaran tidak lengkap.")
            return
        }
        
        saveUser(featurePrints: collectedFeaturePrints)
    }
    
    private func saveUser(featurePrints: [VNFeaturePrintObservation]) {
        do {
            let featureprintData = try NSKeyedArchiver.archivedData(withRootObject: featurePrints, requiringSecureCoding: true)
            let newUser = User(name: userName, faceprintData: featureprintData)
            
            modelContext.insert(newUser)
            try modelContext.save()
            
            DispatchQueue.main.async {
                self.alertMessage = "Pendaftaran wajah untuk \(userName) berhasil! Total \(featurePrints.count) data wajah tersimpan."
                self.registrationSuccess = true
                self.showAlert = true
                self.isProcessing = false
            }
        } catch {
            showError(message: "Gagal menyimpan data pengguna: \(error.localizedDescription)")
        }
    }
    
    private func showError(message: String) {
        DispatchQueue.main.async {
            self.alertMessage = message
            self.registrationSuccess = false
            self.showAlert = true
            self.isProcessing = false
        }
    }
}
