import SwiftUI
import Vision
import SwiftData

@MainActor
class PhotoRegistrationViewModel: ObservableObject, ImprovedRealtimeCameraServiceDelegate {
    @Published var statusMessage: String = "Posisikan wajah di dalam bingkai"
    @Published var isFinished: Bool = false
    @Published var faceObservation: VNFaceObservation?
    
    let cameraService = ImprovedRealtimeCameraService()
    private let userName: String
    private var isAttemptingCapture = false
    private var modelContext: ModelContext?
    private var onComplete: (() -> Void)?

    init(userName: String) {
        self.userName = userName
        self.cameraService.delegate = self
    }

    func start() { cameraService.prepare(); cameraService.startSession() }
    func stop() { cameraService.stopSession() }

    func setDependencies(context: ModelContext, onComplete: @escaping () -> Void) {
        self.modelContext = context
        self.onComplete = onComplete
    }
    
    func attemptRegistration() {
        self.statusMessage = "Menganalisis..."
        self.isAttemptingCapture = true
    }

    func cameraService(didProduce scanResult: ScanResult) {
        var currentObservation: VNFaceObservation?
        switch scanResult {
        case .searching, .multipleFaces, .error, .verifying:
            currentObservation = nil
        case .lowQuality(let obs, _), .noMatch(let obs, _), .match(_, let obs, _):
            currentObservation = obs
        }
        self.faceObservation = currentObservation

        guard isAttemptingCapture else { return }
        self.isAttemptingCapture = false

        var face: VNFaceObservation?
        var buffer: CVPixelBuffer?
        switch scanResult {
        case .lowQuality(let obs, let pb), .noMatch(let obs, let pb), .match(_, let obs, let pb):
            face = obs; buffer = pb
        default:
            handleFailure("Wajah tidak ditemukan."); return
        }
        
        guard let finalFace = face, let finalBuffer = buffer else {
            handleFailure("Error internal, coba lagi."); return
        }
        
        guard let image = CGImage.create(from: finalBuffer) else {
            handleFailure("Gagal memproses frame."); return
        }
        
        statusMessage = "Menyimpan fitur..."
        ImprovedFaceNetService.shared.generateEmbedding(from: image, for: finalFace) { [weak self] values in
            guard let self = self, let values = values else {
                self?.handleFailure("Gagal membuat fitur wajah."); return
            }
            self.saveUser(embedding: FacialVector(values: values))
        }
    }

    private func handleFailure(_ message: String) {
        DispatchQueue.main.async {
            self.statusMessage = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.statusMessage = "Posisikan wajah di dalam bingkai" }
        }
    }

    private func saveUser(embedding: FacialVector) {
        guard let context = modelContext, let onComplete = onComplete else {
            handleFailure("Error Internal."); return
        }
        do {
            let data = try JSONEncoder().encode(embedding)
            let newUser = User(name: self.userName, facialEmbeddingData: data)
            context.insert(newUser)
            try context.save()
            self.isFinished = true
            self.statusMessage = "Pendaftaran Berhasil!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { onComplete() }
        } catch {
            handleFailure("Gagal menyimpan data.")
        }
    }
}
