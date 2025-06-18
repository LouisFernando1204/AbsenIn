//
//  RealtimeCameraService.swift
//  AbsenIn
//
//  Created by Louis Fernando on 17/06/25.
//

import AVFoundation
import Vision
import SwiftUI

// Delegate yang lebih sederhana dan jelas
protocol RealtimeCameraServiceDelegate: AnyObject {
    @MainActor
    func cameraService(didDetectFaces faces: [DetectedFace], videoDimensions: CMVideoDimensions?)
}

class RealtimeCameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let session = AVCaptureSession()
    weak var delegate: RealtimeCameraServiceDelegate?
    
    private var registeredUsers: [User] = []
    private var isProcessingFrame = false
    private var videoDimensions: CMVideoDimensions?
    
    override init() {
        super.init()
        setupSession()
    }
    
    func updateRegisteredUsers(_ users: [User]) {
        self.registeredUsers = users
    }
    
    private func setupSession() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("Kamera depan tidak ditemukan.")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            // Jalankan pada antrian background dengan prioritas tinggi
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue", qos: .userInitiated))
            
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            session.sessionPreset = .hd1280x720
            session.commitConfiguration()
        } catch {
            print("Gagal setup kamera: \(error)")
        }
    }
    
    func startSession() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.session.startRunning()
        }
    }
    
    func stopSession() {
        if session.isRunning {
            session.stopRunning()
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isProcessingFrame else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        isProcessingFrame = true
        
        if self.videoDimensions == nil, let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            self.videoDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        }
        
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { (request, error) in
            defer { self.isProcessingFrame = false }
            
            guard let faceObservations = request.results as? [VNFaceObservation], !faceObservations.isEmpty else {
                // Jika tidak ada wajah, kirim array kosong ke delegate untuk membersihkan UI
                DispatchQueue.main.async {
                    self.delegate?.cameraService(didDetectFaces: [], videoDimensions: self.videoDimensions)
                }
                return
            }
            
            var detectedFacesInFrame: [DetectedFace] = []
            let dispatchGroup = DispatchGroup()
            
            for faceObservation in faceObservations {
                dispatchGroup.enter()
                self.process(faceObservation, in: pixelBuffer) { detectedFace in
                    if let face = detectedFace {
                        detectedFacesInFrame.append(face)
                    }
                    dispatchGroup.leave()
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                self.delegate?.cameraService(didDetectFaces: detectedFacesInFrame, videoDimensions: self.videoDimensions)
            }
        }
        
        // Menggunakan revisi ke-3 untuk deteksi yang lebih akurat dan stabil.
        faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3
        
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try handler.perform([faceDetectionRequest])
        } catch {
            print("Gagal melakukan request deteksi wajah: \(error)")
            isProcessingFrame = false
        }
    }
    
    private func process(_ faceObservation: VNFaceObservation, in pixelBuffer: CVPixelBuffer, completion: @escaping (DetectedFace?) -> Void) {
        // Pastikan bounding box valid untuk mencegah crash
        let validBoundingBox = faceObservation.boundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        
        // PERBAIKAN: Menggunakan .isEmpty untuk validasi CGRect yang benar.
        guard !validBoundingBox.isEmpty else {
            completion(nil)
            return
        }
        
        let featureprintRequest = VNGenerateImageFeaturePrintRequest()
        featureprintRequest.regionOfInterest = validBoundingBox
        
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            try handler.perform([featureprintRequest])
            
            guard let detectedFeaturePrint = featureprintRequest.results?.first as? VNFeaturePrintObservation else {
                completion(nil)
                return
            }
            
            var bestMatch: (user: User, distance: Float)? = nil
            
            // Bandingkan dengan SEMUA sidik jari yang tersimpan untuk setiap pengguna.
            for user in registeredUsers {
                guard let storedData = user.faceprintData,
                      // Unarchive sebagai array [VNFeaturePrintObservation].
                      let storedPrints = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(storedData) as? [VNFeaturePrintObservation] else { continue }
                
                var lowestDistanceForThisUser: Float = .greatestFiniteMagnitude
                
                // Cari jarak terendah dari semua sidik jari yang dimiliki pengguna ini.
                for storedPrint in storedPrints {
                    var distance: Float = .greatestFiniteMagnitude
                    try detectedFeaturePrint.computeDistance(&distance, to: storedPrint)
                    if distance < lowestDistanceForThisUser {
                        lowestDistanceForThisUser = distance
                    }
                }
                
                // Threshold pengenalan (nilai lebih rendah = lebih ketat). 0.8 adalah titik awal yang baik.
                let recognitionThreshold: Float = 0.8
                
                if lowestDistanceForThisUser < recognitionThreshold && (bestMatch == nil || lowestDistanceForThisUser < bestMatch!.distance) {
                    bestMatch = (user, lowestDistanceForThisUser)
                }
            }
            
            let face: DetectedFace
            if let match = bestMatch {
                face = DetectedFace(
                    boundingBox: faceObservation.boundingBox,
                    name: match.user.name,
                    color: .green,
                    recognizedUser: match.user
                )
            } else {
                face = DetectedFace(
                    boundingBox: faceObservation.boundingBox,
                    name: "Tidak Dikenali",
                    color: .red,
                    recognizedUser: nil
                )
            }
            completion(face)
            
        } catch {
            print("Gagal memproses wajah: \(error)")
            completion(nil)
        }
    }
}
