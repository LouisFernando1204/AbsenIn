import SwiftUI
import Vision
import SwiftData
import AVFoundation

// PERUBAHAN 1: Tambahkan ekstensi ini di bagian atas file (setelah import).
// Ekstensi ini menambahkan fungsi 'isClosed' ke landmark mata.
extension VNFaceLandmarkRegion2D {
    // Menghitung apakah mata tertutup berdasarkan jarak vertikal titik-titiknya.
    // 'faceBoundingBoxHeight' digunakan untuk membuat threshold menjadi relatif dan lebih akurat.
    func isClosed(faceBoundingBoxHeight: CGFloat, threshold: CGFloat = 0.12) -> Bool {
        // Dapatkan semua koordinat Y dari titik-titik mata.
        let yPoints = self.normalizedPoints.map { $0.y }
        
        // Cari titik terendah dan tertinggi.
        guard let minY = yPoints.min(), let maxY = yPoints.max() else {
            return false
        }
        
        // Hitung rentang vertikal (tinggi) dari mata.
        let verticalSpan = maxY - minY
        
        // Hitung rentang relatif terhadap tinggi wajah.
        // Jika tinggi wajah 0, anggap tidak tertutup.
        let relativeSpan = faceBoundingBoxHeight > 0 ? verticalSpan / faceBoundingBoxHeight : 1.0
        
        // Jika rentang relatif sangat kecil, anggap mata tertutup.
        return relativeSpan < threshold
    }
}


@MainActor
class ScanViewModel: ObservableObject {
    @Published var statusMessage: String = "Posisikan wajah di dalam bingkai"
    @Published var isFaceWellPositioned: Bool = false
    
    let cameraService = RealtimeCameraService()
    
    private var modelContext: ModelContext?
    private var todaysAttendedUserIDs = Set<String>()
    private var isScanningPaused = false

    // State untuk Liveness Check
    private var lastBlinkTimestamp: Date?
    private let blinkChallengeInterval: TimeInterval = 3.0

    init() {
        cameraService.delegate = self
    }
    
    func activate(modelContext: ModelContext, registeredUsers: [User]) {
        self.modelContext = modelContext
        self.cameraService.updateRegisteredUsers(registeredUsers)
        self.fetchTodaysAttendance()
        
        cameraService.prepare { [weak self] success in
            guard success else {
                self?.statusMessage = "Kamera tidak dapat diakses."
                return
            }
            self?.cameraService.startSession()
        }
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
    
    private func recordAttendance(for user: User) {
        guard let context = modelContext else { return }
        
        if todaysAttendedUserIDs.contains(user.id) {
            statusMessage = "✅ \(user.name) sudah absen hari ini."
            pauseScanning()
            return
        }
        
        let newRecord = AttendanceRecord(userID: user.id, userName: user.name)
        context.insert(newRecord)
        
        do {
            try context.save()
            todaysAttendedUserIDs.insert(user.id)
            let timeString = Date().formatted(date: .omitted, time: .standard)
            statusMessage = "✅ Absen berhasil: \(user.name) pukul \(timeString)"
            pauseScanning()
            
        } catch {
            print("Gagal menyimpan absensi: \(error)")
            statusMessage = "❌ Gagal menyimpan data absensi."
            pauseScanning()
        }
    }
    
    private func pauseScanning() {
        isScanningPaused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.isScanningPaused = false
        }
    }
}

// PERUBAHAN 2: Ganti implementasi delegate dengan yang baru.
extension ScanViewModel: RealtimeCameraServiceDelegate {
    func cameraService(didDetect observations: [VNFaceObservation], recognizedUsers: [UUID : User?]) {
        if isScanningPaused {
            isFaceWellPositioned = false
            return
        }
        
        guard observations.count == 1, let face = observations.first else {
            isFaceWellPositioned = false
            statusMessage = "Posisikan satu wajah di dalam bingkai"
            lastBlinkTimestamp = nil
            return
        }
        
        isFaceWellPositioned = true
        
        // --- LIVENESS CHECK (DETEKSI KEDIPAN DARI LANDMARK) ---
        guard let landmarks = face.landmarks else {
            statusMessage = "Landmark wajah tidak terdeteksi"
            return
        }
        
        // Gunakan fungsi helper yang kita buat di ekstensi.
        let leftEyeIsClosed = landmarks.leftEye?.isClosed(faceBoundingBoxHeight: face.boundingBox.height) ?? false
        let rightEyeIsClosed = landmarks.rightEye?.isClosed(faceBoundingBoxHeight: face.boundingBox.height) ?? false
        
        if leftEyeIsClosed && rightEyeIsClosed {
            lastBlinkTimestamp = Date()
        }
        
        if let lastBlink = lastBlinkTimestamp {
            if Date().timeIntervalSince(lastBlink) > blinkChallengeInterval {
                statusMessage = "Mohon berkedip untuk verifikasi"
                lastBlinkTimestamp = nil
                return
            }
        } else {
            statusMessage = "Mohon berkedip untuk verifikasi"
            return
        }
        
        // --- JIKA LIVENESS CHECK LOLOS, LANJUTKAN ---
        
        if let recognizedResult = recognizedUsers[face.uuid], let user = recognizedResult {
            recordAttendance(for: user)
        } else {
            statusMessage = "Wajah tidak dikenali"
        }
    }
}
