import SwiftUI
import Vision
import SwiftData

@MainActor
class PhotoRegistrationViewModel: ObservableObject {
    let totalPhotosToCapture = 25

    @Published var photosCapturedCount = 0
    @Published var isFinished = false
    @Published var statusMessage = "Bersiap..."
    
    private var hasSavedUser = false

    let photoService = PhotoCaptureService()
    private let userName: String
    private var captureTimer: Timer?
    private var capturedFeaturePrints: [VNFeaturePrintObservation] = []
    
    private let registrationInstructions: [(text: String, symbol: String)] = [
        ("Lihat lurus ke depan", "arrow.down.forward.and.arrow.up.backward"),
        ("Putar kepala sedikit ke kiri", "arrow.left"),
        ("Putar kepala sedikit ke kanan", "arrow.right"),
        ("Angkat dagu sedikit", "arrow.up"),
        ("Tundukkan dagu sedikit", "arrow.down")
    ]
    
    @Published private var instructionIndex = 0

    var currentInstructionText: String {
        guard instructionIndex < registrationInstructions.count else { return "Selesai!" }
        return registrationInstructions[instructionIndex].text
    }

    var currentInstructionSymbol: String {
        guard instructionIndex < registrationInstructions.count else { return "checkmark.circle.fill" }
        return registrationInstructions[instructionIndex].symbol
    }

    init(userName: String) {
        self.userName = userName
    }

    func startRegistration() {
        statusMessage = "Posisikan wajah di dalam bingkai"
        photoService.startRunning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.startCapturingPhotos()
        }
    }

    private func startCapturingPhotos() {
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            // PERBAIKAN 1: Membuka 'self' sebelum digunakan
            guard let self = self else { return }
            self.captureAndProcessPhoto()
        }
    }

    private func captureAndProcessPhoto() {
        guard !isFinished else { return }
        
        photoService.capturePhoto { [weak self] image in
            // PERBAIKAN 2: Anda sudah punya guard di sini, jadi ini sudah benar.
            // Namun, logic di dalamnya akan saya perbaiki sedikit agar lebih aman.
            guard let self = self else { return }
            
            guard let image = image else {
                self.statusMessage = "Gagal mengambil foto. Coba lagi."
                return
            }
            self.processImage(image)
        }
    }
    
    private func processImage(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }

        let faceDetectionRequest = VNDetectFaceRectanglesRequest { [weak self] (request, error) in
            // PERBAIKAN 3: Membuka 'self' di awal closure
            guard let self = self else { return }
            
            guard let results = request.results as? [VNFaceObservation],
                  let face = results.first else {
                DispatchQueue.main.async {
                    self.statusMessage = "Wajah tidak terdeteksi."
                }
                return
            }
            
            guard let faceImage = self.cropFace(from: image, with: face.boundingBox) else {
                DispatchQueue.main.async {
                    self.statusMessage = "Gagal memotong gambar wajah."
                }
                return
            }
            
            guard let croppedCGImage = faceImage.cgImage else { return }
            
            let handler = VNImageRequestHandler(cgImage: croppedCGImage, orientation: .up)
            let featurePrintRequest = VNGenerateImageFeaturePrintRequest()
            
            do {
                try handler.perform([featurePrintRequest])
                if let featurePrint = featurePrintRequest.results?.first {
                    DispatchQueue.main.async {
                        self.handleSuccessfulCapture(with: featurePrint)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.statusMessage = "Gagal memproses fitur wajah."
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Error proses: \(error.localizedDescription)"
                }
            }
        }
        faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3

        do {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .leftMirrored)
            try handler.perform([faceDetectionRequest])
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Error deteksi: \(error.localizedDescription)"
            }
        }
    }
    
    private func cropFace(from image: UIImage, with boundingBox: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        let cropRect = CGRect(
            x: boundingBox.origin.x * imageWidth,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageHeight,
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        )
        
        if let croppedCGImage = cgImage.cropping(to: cropRect) {
            return UIImage(cgImage: croppedCGImage)
        }
        
        return nil
    }

    private func handleSuccessfulCapture(with featurePrint: VNFeaturePrintObservation) {
        capturedFeaturePrints.append(featurePrint)
        photosCapturedCount += 1
        
        let photosPerInstruction = totalPhotosToCapture / registrationInstructions.count
        if photosCapturedCount % photosPerInstruction == 0 && photosCapturedCount < totalPhotosToCapture {
            instructionIndex += 1
        }
        
        if photosCapturedCount >= totalPhotosToCapture {
            isFinished = true
            captureTimer?.invalidate()
            photoService.stopRunning()
            statusMessage = "Pengambilan data selesai!"
        } else {
            statusMessage = "Foto \(photosCapturedCount) dari \(totalPhotosToCapture) berhasil..."
        }
    }

    func saveUser(context: ModelContext, completion: @escaping () -> Void) {
        guard !hasSavedUser else { return }
        hasSavedUser = true
        guard !capturedFeaturePrints.isEmpty else { completion(); return }
        do {
            let featurePrintData = try NSKeyedArchiver.archivedData(withRootObject: capturedFeaturePrints, requiringSecureCoding: true)
            let newUser = User(name: userName, facialVectorData: featurePrintData)
            context.insert(newUser)
            try context.save()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { completion() }
        } catch {
            print("❌ Gagal menyimpan pengguna: \(error)")
            completion()
        }
    }
}
