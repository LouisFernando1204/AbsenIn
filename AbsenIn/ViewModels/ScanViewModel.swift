import SwiftUI
import Vision
import SwiftData

@MainActor
class ScanViewModel: ObservableObject, ImprovedRealtimeCameraServiceDelegate {
    @Published private(set) var scanResult: ScanResult = .searching
    @Published var faceObservation: VNFaceObservation?
    @Published var isMatch: Bool = false
    let cameraService = ImprovedRealtimeCameraService()
    private var modelContext: ModelContext?
    private var todaysAttendedUserIDs = Set<String>()
    
    var statusMessage: String {
        switch scanResult {
        case .searching: return "Posisikan wajah di dalam bingkai"
        case .lowQuality: return "Wajah terlalu jauh atau tidak jelas"
        case .verifying: return "Memverifikasi..."
        case .match(let user, _, _):
            if todaysAttendedUserIDs.contains(user.id) { return "✅ \(user.name) sudah absen hari ini." }
            let time = Date().formatted(date: .omitted, time: .standard)
            return "✅ Absen berhasil: \(user.name) pukul \(time)"
        case .noMatch: return "Wajah tidak dikenali"
        case .multipleFaces: return "Terdeteksi lebih dari satu wajah"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    init() { cameraService.delegate = self }
    
    func activate(modelContext: ModelContext, registeredUsers: [User]) {
        self.modelContext = modelContext
        cameraService.updateRegisteredUsers(registeredUsers)
        fetchTodaysAttendance()
        cameraService.prepare()
        cameraService.startSession()
    }
    
    func deactivate() { cameraService.stopSession() }
    
    private func fetchTodaysAttendance() {
        guard let context = modelContext else { return }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = #Predicate<AttendanceRecord> { $0.timestamp >= startOfDay }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let records = try? context.fetch(descriptor) { self.todaysAttendedUserIDs = Set(records.map { $0.userID }) }
    }
    
    private func processSuccessfulMatch(for user: User) {
        guard !todaysAttendedUserIDs.contains(user.id) else { return }
        guard let context = modelContext else { return }
        let newRecord = AttendanceRecord(userID: user.id, userName: user.name)
        context.insert(newRecord)
        do { try context.save(); todaysAttendedUserIDs.insert(user.id) } catch { print("Failed to save attendance.") }
    }

    func cameraService(didProduce scanResult: ScanResult) {
        self.scanResult = scanResult
        self.isMatch = false
        switch scanResult {
        case .searching, .multipleFaces, .error:
            self.faceObservation = nil
        case .lowQuality(let observation, _), .noMatch(let observation, _):
            self.faceObservation = observation
        case .verifying:
            break
        case .match(let user, let observation, _):
            self.faceObservation = observation
            self.isMatch = true
            processSuccessfulMatch(for: user)
        }
    }
}
