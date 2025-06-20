import SwiftUI
import Vision
import SwiftData
import AVFoundation

@MainActor
class ScanViewModel: ObservableObject {
    @Published var statusMessage: String = "Posisikan wajah di dalam bingkai"
    @Published var isFaceWellPositioned: Bool = false
    
    let cameraService = RealtimeCameraService()
    
    private var modelContext: ModelContext?
    private var todaysAttendedUserIDs = Set<String>()
    
    private var isScanningPaused = false

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

extension ScanViewModel: RealtimeCameraServiceDelegate {
    func cameraService(didDetect faces: [DetectedFace]) {
        if isScanningPaused {
            isFaceWellPositioned = false
            return
        }
        
        guard faces.count == 1, let face = faces.first else {
            isFaceWellPositioned = false
            statusMessage = "Posisikan satu wajah di dalam bingkai"
            return
        }
        
        isFaceWellPositioned = true
        
        if let user = face.recognizedUser {
            recordAttendance(for: user)
        } else {
            statusMessage = "Wajah tidak dikenali"
        }
    }
}
