import SwiftUI
import Vision
import SwiftData

@MainActor
class PhotoRegistrationViewModel: ObservableObject {
    enum Pose: CaseIterable {
        case center, left, right, up, down
        var instruction: String {
            switch self {
            case .center: return "Lihat lurus ke depan dan tahan"
            case .left: return "Lihat ke kiri dan tahan"
            case .right: return "Lihat ke kanan dan tahan"
            case .up: return "Lihat ke atas dan tahan"
            case .down: return "Lihat ke bawah dan tahan"
            }
        }
    }
    
    @Published var currentPoseIndex = 0
    @Published var photosForCurrentPoseCount = 0
    @Published var isFinished = false
    @Published var statusMessage = ""
    
    let photoService = PhotoCaptureService()
    private let userName: String
    private var captureTimer: Timer?
    private var capturedVectors: [FacialVector] = []
    private var isWaitingForNextPose = false
    
    var totalPoses: Int { Pose.allCases.count }
    var currentInstruction: String {
        guard currentPoseIndex < Pose.allCases.count else { return "Selesai!" }
        return Pose.allCases[currentPoseIndex].instruction
    }

    init(userName: String) { self.userName = userName }

    func startRegistration() {
        statusMessage = "Bersiap..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.startNextPose() }
    }
    
    private func startNextPose() {
        guard currentPoseIndex < totalPoses else {
            if !isFinished { isFinished = true }
            return
        }
        photosForCurrentPoseCount = 0
        isWaitingForNextPose = false
        statusMessage = "Tahan posisi..."
        
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.captureAndProcessPhoto()
            }
        }
    }

    private func captureAndProcessPhoto() {
        guard !isWaitingForNextPose else { return }
        photoService.capturePhoto { [weak self] image in
            guard let self = self, let image = image else { return }
            self.processImage(image)
        }
    }

    private func processImage(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        let landmarksRequest = VNDetectFaceLandmarksRequest { [weak self] request, error in
            guard let self = self else { return }
            
            guard let results = request.results as? [VNFaceObservation], let firstFace = results.first else {
                DispatchQueue.main.async {
                    self.statusMessage = "Wajah tidak terdeteksi. Posisikan wajah Anda."
                }
                return
            }
            
            if let facialVector = firstFace.landmarks?.toFacialVector() {
                DispatchQueue.main.async {
                    self.handleSuccessfulCapture(with: facialVector)
                }
            }
        }
        
        try? requestHandler.perform([landmarksRequest])
    }

    private func handleSuccessfulCapture(with vector: FacialVector) {
        guard !isWaitingForNextPose else { return }
        
        self.capturedVectors.append(vector)
        self.photosForCurrentPoseCount += 1
        self.statusMessage = "Foto \(self.photosForCurrentPoseCount) dari 5 berhasil!"
        
        if self.photosForCurrentPoseCount >= 5 {
            self.isWaitingForNextPose = true
            self.captureTimer?.invalidate()
            self.currentPoseIndex += 1
            
            if self.currentPoseIndex >= self.totalPoses {
                self.statusMessage = "Semua foto berhasil diambil!"
                if !self.isFinished { self.isFinished = true }
            } else {
                self.statusMessage = "Bagus! Siap untuk pose berikutnya..."
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.startNextPose() }
            }
        }
    }

    func saveUser(context: ModelContext, completion: @escaping () -> Void) {
        guard !capturedVectors.isEmpty else {
            print("Data registrasi tidak lengkap."); completion(); return
        }
        do {
            let vectorData = try JSONEncoder().encode(capturedVectors)
            let newUser = User(name: userName, facialVectorData: vectorData)
            context.insert(newUser)
            try context.save()
            print("Pengguna baru berhasil disimpan: \(userName)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { completion() }
        } catch {
            print("Gagal menyimpan pengguna: \(error)"); completion()
        }
    }
}
