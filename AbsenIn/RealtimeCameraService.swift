//
//  RealtimeCameraService.swift
//  AbsenIn
//
//  Created by Louis Fernando on 17/06/25.
//

import AVFoundation
import Vision
import CoreImage

protocol FaceRecognitionDelegate: AnyObject {
    // Diubah untuk mengirimkan Array dari User, untuk mendukung multi-wajah
    func didRecognize(users: [User])
    func didFailToRecognize()
}

class RealtimeCameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    weak var delegate: FaceRecognitionDelegate?
    
    let session = AVCaptureSession()
    private var registeredUsers: [User] = []
    private var recentlyRecognizedIDs = Set<String>()
    
    // Flag untuk mencegah penumpukan frame processing
    private var isProcessingFrame = false

    func startSession(registeredUsers: [User]) {
        self.registeredUsers = registeredUsers
        guard !session.isRunning else { return }
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("No front camera found"); return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue", qos: .userInitiated))

            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            session.sessionPreset = .hd1280x720
            session.commitConfiguration()
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        } catch {
            print("Failed to set up camera: \(error.localizedDescription)")
        }
    }
    
    func stopSession() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessingFrame else { return }
        self.isProcessingFrame = true
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            self.isProcessingFrame = false
            return
        }

        let faceDetectionRequest = VNDetectFaceRectanglesRequest { (request, error) in
            defer {
                // Pastikan flag selalu di-reset di akhir
                DispatchQueue.main.async {
                    self.isProcessingFrame = false
                }
            }
            
            guard let faceObservations = request.results as? [VNFaceObservation], !faceObservations.isEmpty else {
                DispatchQueue.main.async { self.delegate?.didFailToRecognize() }
                return
            }
            
            // Proses semua wajah yang ditemukan secara paralel
            var recognizedUsersInFrame: [User] = []
            let dispatchGroup = DispatchGroup()

            for faceObservation in faceObservations {
                dispatchGroup.enter()
                self.findBestMatch(for: faceObservation, in: pixelBuffer) { bestMatchUser in
                    if let user = bestMatchUser {
                        recognizedUsersInFrame.append(user)
                    }
                    dispatchGroup.leave()
                }
            }
            
            // Setelah semua perbandingan selesai...
            dispatchGroup.notify(queue: .main) {
                if !recognizedUsersInFrame.isEmpty {
                    let newRecognitions = recognizedUsersInFrame.filter { !self.recentlyRecognizedIDs.contains($0.id) }
                    
                    if !newRecognitions.isEmpty {
                        newRecognitions.forEach { self.recentlyRecognizedIDs.insert($0.id) }
                        self.delegate?.didRecognize(users: newRecognitions)

                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            newRecognitions.forEach { self.recentlyRecognizedIDs.remove($0.id) }
                        }
                    }
                } else {
                    // Ada wajah, tapi tidak ada yang cocok
                    self.delegate?.didFailToRecognize()
                }
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([faceDetectionRequest])
    }
    
    private func findBestMatch(for faceObservation: VNFaceObservation, in pixelBuffer: CVPixelBuffer, completion: @escaping (User?) -> Void) {
        let originalImage = CIImage(cvPixelBuffer: pixelBuffer)
        let boundingBox = faceObservation.boundingBox
        let faceImageRect = VNImageRectForNormalizedRect(boundingBox, Int(originalImage.extent.width), Int(originalImage.extent.height))
        let croppedFaceImage = originalImage.cropped(to: faceImageRect)

        let featureprintRequest = VNGenerateImageFeaturePrintRequest()
        
        do {
            let handler = VNImageRequestHandler(ciImage: croppedFaceImage, options: [:])
            try handler.perform([featureprintRequest])

            guard let detectedFeaturePrint = featureprintRequest.results?.first as? VNFeaturePrintObservation else {
                completion(nil)
                return
            }
            
            // --- PERBAIKAN AKURASI UTAMA ADA DI SINI ---
            let bestMatch = registeredUsers.compactMap { user -> (user: User, distance: Float)? in
                guard let storedData = user.faceprintData,
                      let storedPrint = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(storedData) as? VNFeaturePrintObservation else { return nil }

                var distance: Float = .greatestFiniteMagnitude
                do {
                    try detectedFeaturePrint.computeDistance(&distance, to: storedPrint)
                    return (user, distance)
                } catch {
                    // Gagal membandingkan, anggap tidak cocok
                    return nil
                }
            }
            // Filter dengan threshold yang lebih ketat dan ambil yang terbaik
            .filter { $0.distance < 0.65 } // << THRESHOLD DIPERKETAT
            .min(by: { $0.distance < $1.distance })
            
            completion(bestMatch?.user)

        } catch {
            print("Failed to generate feature print for a face: \(error)")
            completion(nil)
        }
    }
}
