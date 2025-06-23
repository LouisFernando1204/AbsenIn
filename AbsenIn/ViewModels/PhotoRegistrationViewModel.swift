// PhotoRegistrationViewModel.swift (FINAL YANG BENAR - DENGAN CROPPING)

import SwiftUI
import Vision
import SwiftData

@MainActor
class PhotoRegistrationViewModel: ObservableObject {
    private let totalPhotosToCapture = 25

    @Published var photosCapturedCount = 0
    @Published var isFinished = false
    @Published var statusMessage = "Bersiap..."
    
    private var hasSavedUser = false

    let photoService = PhotoCaptureService()
    private let userName: String
    private var captureTimer: Timer?
    private var capturedFeaturePrints: [VNFeaturePrintObservation] = []
    
    private let registrationInstructions = [
        "Lihat lurus ke depan",
        "Putar kepala sedikit ke kiri",
        "Putar kepala sedikit ke kanan",
        "Angkat dagu sedikit",
        "Tundukkan dagu sedikit"
    ]
    private var instructionIndex = 0

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
        statusMessage = registrationInstructions[instructionIndex]
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.captureAndProcessPhoto()
        }
    }

    private func captureAndProcessPhoto() {
        guard !isFinished else { return }
        
        photoService.capturePhoto { [weak self] image in
            guard let self = self, let image = image else {
                DispatchQueue.main.async { self?.statusMessage = "Gagal mengambil foto. Coba lagi." }
                return
            }
            self.processImage(image)
        }
    }
    
    // =================================================================
    // FUNGSI INTI DENGAN LOGIKA CROPPING YANG BENAR
    // =================================================================
    private func processImage(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }

        // Langkah 1: Deteksi kotak wajah pada gambar penuh
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { [weak self] (request, error) in
            guard let self = self,
                  let results = request.results as? [VNFaceObservation],
                  let face = results.first else {
                DispatchQueue.main.async { self?.statusMessage = "Wajah tidak terdeteksi." }
                return
            }
            
            // Langkah 2: CROP gambar asli HANYA pada bagian wajah
            guard let faceImage = self.cropFace(from: image, with: face.boundingBox) else {
                DispatchQueue.main.async { self.statusMessage = "Gagal memotong gambar wajah." }
                return
            }
            
            // Langkah 3: Buat feature print dari GAMBAR HASIL CROP
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
                    DispatchQueue.main.async { self.statusMessage = "Gagal memproses fitur wajah." }
                }
            } catch {
                DispatchQueue.main.async { self.statusMessage = "Error proses: \(error.localizedDescription)" }
            }
        }
        faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3

        // Eksekusi deteksi pada gambar penuh
        do {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .leftMirrored)
            try handler.perform([faceDetectionRequest])
        } catch {
            DispatchQueue.main.async { self.statusMessage = "Error deteksi: \(error.localizedDescription)" }
        }
    }
    
    /// Fungsi helper untuk memotong UIImage berdasarkan bounding box dari Vision
    private func cropFace(from image: UIImage, with boundingBox: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        // Koordinat Vision (bawah-kiri) berbeda dengan Core Graphics (atas-kiri).
        // Kita perlu mengonversinya.
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        let cropRect = CGRect(
            x: boundingBox.origin.x * imageWidth,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageHeight,
            width: boundingBox.width * imageWidth,
            height: boundingBox.height * imageHeight
        )
        
        // Lakukan cropping
        if let croppedCGImage = cgImage.cropping(to: cropRect) {
            return UIImage(cgImage: croppedCGImage)
        }
        
        return nil
    }

    // Fungsi handleSuccessfulCapture dan saveUser tidak perlu diubah
    private func handleSuccessfulCapture(with featurePrint: VNFeaturePrintObservation) {
        capturedFeaturePrints.append(featurePrint)
        photosCapturedCount += 1
        
        if photosCapturedCount % 5 == 0 && photosCapturedCount < totalPhotosToCapture {
            instructionIndex += 1
            if instructionIndex < registrationInstructions.count {
                statusMessage = registrationInstructions[instructionIndex]
            }
        }

        if photosCapturedCount >= totalPhotosToCapture {
            isFinished = true
            captureTimer?.invalidate()
            photoService.stopRunning()
            statusMessage = "Pengambilan data selesai!"
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
