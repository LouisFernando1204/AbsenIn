// ScanViewModel.swift (GANTI SELURUH FILE)

import SwiftUI
import Vision
import SwiftData

@MainActor
class ScanViewModel: ObservableObject {
    @Published var statusMessage: String = "Posisikan wajah di dalam bingkai"
    @Published var isFaceDetected: Bool = false // Hanya untuk feedback UI
    
    let cameraService = RealtimeCameraService()
    private var modelContext: ModelContext?
    private var todaysAttendedUserIDs = Set<String>()
    
    // Flag untuk memastikan kita tidak memproses absensi berkali-kali dalam satu sesi pengenalan
    private var isProcessingAttendance = false

    init() {
        cameraService.delegate = self
    }
    
    func activate(modelContext: ModelContext, registeredUsers: [User]) {
        self.modelContext = modelContext
        self.isProcessingAttendance = false // Reset saat diaktifkan
        
        self.cameraService.updateRegisteredUsers(registeredUsers)
        self.fetchTodaysAttendance()
        
        cameraService.prepare { [weak self] success in
            guard let self = self else { return }
            guard success else {
                self.statusMessage = "Kamera tidak dapat diakses."
                return
            }
            self.cameraService.startSession()
        }
    }
    
    private func fetchTodaysAttendance() {
        // ... (fungsi ini sudah benar, tidak perlu diubah)
        guard let context = modelContext else { return }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        let predicate = #Predicate<AttendanceRecord> { record in
            record.timestamp >= startOfDay && record.timestamp < endOfDay
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let todaysRecords = try? context.fetch(descriptor) {
            self.todaysAttendedUserIDs = Set(todaysRecords.map { $0.userID })
        }
    }
    
    private func recordAttendance(for user: User) {
        guard !isProcessingAttendance, let context = modelContext else { return }
        isProcessingAttendance = true // Kunci proses absensi
        
        if todaysAttendedUserIDs.contains(user.id) {
            statusMessage = "✅ \(user.name) sudah absen hari ini."
            resetAfterDelay()
            return
        }
        
        let newRecord = AttendanceRecord(userID: user.id, userName: user.name)
        context.insert(newRecord)
        
        do {
            try context.save()
            todaysAttendedUserIDs.insert(user.id)
            let timeString = Date().formatted(date: .omitted, time: .standard)
            statusMessage = "✅ Absen berhasil: \(user.name) pukul \(timeString)"
            resetAfterDelay()
        } catch {
            print("Gagal menyimpan absensi: \(error)")
            statusMessage = "❌ Gagal menyimpan data absensi."
            isProcessingAttendance = false // Buka kunci jika gagal
        }
    }
    
    // Reset status setelah beberapa detik
    private func resetAfterDelay(seconds: TimeInterval = 3.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            self.isProcessingAttendance = false
            self.statusMessage = "Posisikan wajah di dalam bingkai"
        }
    }
}

// Implementasi delegate yang lebih ringkas
extension ScanViewModel: RealtimeCameraServiceDelegate {
    func cameraService(didDetect observations: [VNFaceObservation], recognizedUsers: [UUID : User?]) {
        // Jangan ubah status jika sedang menampilkan pesan sukses/gagal
        if isProcessingAttendance {
            return
        }

        guard let face = observations.first else {
            isFaceDetected = false
            statusMessage = observations.isEmpty ? "Posisikan wajah di dalam bingkai" : "Hanya satu wajah yang diizinkan"
            return
        }
        
        isFaceDetected = true
        
        // Periksa hasil pengenalan dari service
        if let recognizedResult = recognizedUsers[face.uuid] {
            if let user = recognizedResult {
                // Pengguna dikenali, catat absensi
                recordAttendance(for: user)
            } else {
                // Wajah terdeteksi tapi tidak cocok dengan siapa pun
                statusMessage = "Wajah tidak dikenali"
            }
        } else {
            // Wajah terdeteksi, sedang dalam proses verifikasi...
             statusMessage = "Memverifikasi..."
        }
    }
}
