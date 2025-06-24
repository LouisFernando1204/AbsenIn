// ScanViewModel.swift (FINAL - Perbaikan Pesan Sukses yang Hilang)

import SwiftUI
import Vision
import SwiftData

@MainActor
class ScanViewModel: ObservableObject {
    @Published var statusMessage: String = "Posisikan wajah di dalam bingkai"
    @Published var isFaceDetected: Bool = false
    
    let cameraService = RealtimeCameraService()
    private var modelContext: ModelContext?
    private var todaysAttendedUserIDs = Set<String>()
    
    // State baru untuk menandai kita sedang dalam fase cooldown SETELAH pesan sukses ditampilkan.
    private var isDisplayingSuccessMessage = false

    init() {
        cameraService.delegate = self
    }
    
    func activate(modelContext: ModelContext, registeredUsers: [User]) {
        self.modelContext = modelContext
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
    
    func deactivate() {
        cameraService.stopSession()
    }
    
    private func fetchTodaysAttendance() {
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
    
    // Fungsi ini sekarang mengatur pesan sukses dan flag penanda
    private func processSuccessfulRecognition(for user: User) {
        // Jangan proses jika sudah dalam mode menampilkan pesan sukses
        guard !isDisplayingSuccessMessage else { return }
        
        // Aktifkan mode menampilkan pesan sukses
        isDisplayingSuccessMessage = true
        
        // Cek apakah sudah absen
        if todaysAttendedUserIDs.contains(user.id) {
            statusMessage = "✅ \(user.name) sudah absen hari ini."
        } else {
            // Catat absensi
            guard let context = modelContext else { return }
            let newRecord = AttendanceRecord(userID: user.id, userName: user.name)
            context.insert(newRecord)
            do {
                try context.save()
                todaysAttendedUserIDs.insert(user.id)
                let timeString = Date().formatted(date: .omitted, time: .standard)
                statusMessage = "✅ Absen berhasil: \(user.name) pukul \(timeString)"
            } catch {
                statusMessage = "❌ Gagal menyimpan data."
            }
        }
        
        // Atur timer untuk mengakhiri mode pesan sukses
        // Durasi harus sama dengan lock di service
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.isDisplayingSuccessMessage = false
            // Reset pesan ke default setelah jeda selesai
            self.statusMessage = "Posisikan wajah di dalam bingkai"
        }
    }
}

// MARK: - RealtimeCameraServiceDelegate
extension ScanViewModel: RealtimeCameraServiceDelegate {
    
    func cameraService(didDetect observations: [VNFaceObservation], recognizedUsers: [UUID : User?]) {
        
        // PERUBAHAN LOGIKA UTAMA DI SINI:
        // Jika kita sedang menampilkan pesan sukses, jangan lakukan apa-apa. Biarkan pesan itu tampil.
        if isDisplayingSuccessMessage {
            isFaceDetected = !observations.isEmpty // Tetap update overlay
            return
        }

        guard let face = observations.first else {
            isFaceDetected = false
            statusMessage = "Posisikan wajah di dalam bingkai"
            return
        }
        
        isFaceDetected = true

        if let recognizedResult = recognizedUsers[face.uuid] {
            // Service memberikan hasil (tidak sedang di-lock)
            if let user = recognizedResult {
                // Pengguna dikenali -> mulai siklus sukses
                processSuccessfulRecognition(for: user)
            } else {
                // Wajah terdeteksi tapi tidak cocok
                statusMessage = "Wajah tidak dikenali"
            }
        } else {
            // Service TIDAK memberikan hasil (karena sedang di-lock)
            // Pesan ini hanya akan muncul sebelum pengenalan pertama berhasil
            statusMessage = "Memverifikasi..."
        }
    }
}
