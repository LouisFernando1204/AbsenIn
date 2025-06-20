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
    private var recentlyRecognizedUserIDs = Set<String>()
    
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
        guard let context = modelContext,
              !todaysAttendedUserIDs.contains(user.id) else {
            // This case is now handled by the delegate, but we keep the guard for safety.
            return
        }
        
        recentlyRecognizedUserIDs.insert(user.id)
        
        let newRecord = AttendanceRecord(userID: user.id, userName: user.name)
        context.insert(newRecord)
        
        do {
            try context.save()
            todaysAttendedUserIDs.insert(user.id)
            
            let timeString = Date().formatted(date: .omitted, time: .standard)
            statusMessage = "✅ Absen berhasil: \(user.name) pukul \(timeString)"
            
            isScanningPaused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.isScanningPaused = false
                self.statusMessage = "Posisikan wajah di dalam bingkai"
            }
            
        } catch {
            print("Gagal menyimpan absensi: \(error)")
            statusMessage = "❌ Gagal menyimpan data absensi."
        }
    }
}

extension ScanViewModel: RealtimeCameraServiceDelegate {
    func cameraService(didDetect faces: [DetectedFace]) {
        if isScanningPaused {
            self.isFaceWellPositioned = false
            return
        }
        
        guard faces.count == 1, let face = faces.first else {
            self.isFaceWellPositioned = false
            self.statusMessage = "Posisikan satu wajah di dalam bingkai"
            return
        }
        
        self.isFaceWellPositioned = true
        
        if let user = face.recognizedUser {
            if todaysAttendedUserIDs.contains(user.id) {
                statusMessage = "✅ \(user.name) sudah absen hari ini."
                isScanningPaused = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    self.isScanningPaused = false
                    self.statusMessage = "Posisikan wajah di dalam bingkai"
                }
            } else {
                recordAttendance(for: user)
            }
        } else {
            self.statusMessage = "Wajah tidak dikenali"
        }
    }
}
