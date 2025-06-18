//
//  ScanViewModel.swift
//  AbsenIn
//
//  Created by Louis Fernando on 18/06/25.
//

import SwiftUI
import Vision
import SwiftData
import AVFoundation

struct DetectedFace: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let name: String?
    let color: Color
    let recognizedUser: User?
}

@MainActor
class ScanViewModel: ObservableObject {
    @Published var detectedFaces: [DetectedFace] = []
    @Published var statusMessage: String = ""
    
    let cameraService = RealtimeCameraService()
    
    private var modelContext: ModelContext?
    private var todaysAttendedUserIDs = Set<String>()
    private var videoDimensions: CMVideoDimensions?
    
    init() {
        cameraService.delegate = self
    }
    
    func setup(modelContext: ModelContext, registeredUsers: [User]) {
        self.modelContext = modelContext
        self.cameraService.updateRegisteredUsers(registeredUsers)
        fetchTodaysAttendance()
    }
    
    func convertRect(for normalizedRect: CGRect, in viewSize: CGSize) -> CGRect {
        guard let videoDimensions = self.videoDimensions else { return .zero }
        
        let videoWidth = CGFloat(videoDimensions.width)
        let videoHeight = CGFloat(videoDimensions.height)
        
        var uiKitRect = VNImageRectForNormalizedRect(normalizedRect, Int(videoWidth), Int(videoHeight))
        uiKitRect.origin.y = videoHeight - uiKitRect.origin.y - uiKitRect.height
        
        let viewAspectRatio = viewSize.width / viewSize.height
        let videoAspectRatio = videoWidth / videoHeight
        
        var scale: CGFloat = 0.0
        var xOffset: CGFloat = 0.0
        var yOffset: CGFloat = 0.0
        
        if videoAspectRatio > viewAspectRatio {
            scale = viewSize.height / videoHeight
            xOffset = (viewSize.width - videoWidth * scale) / 2.0
        } else {
            scale = viewSize.width / videoWidth
            yOffset = (viewSize.height - videoHeight * scale) / 2.0
        }
        
        var finalRect = CGRect(
            x: uiKitRect.origin.x * scale + xOffset,
            y: uiKitRect.origin.y * scale + yOffset,
            width: uiKitRect.width * scale,
            height: uiKitRect.height * scale
        )
        
        // PERBAIKAN KUNCI: Balik koordinat X karena kamera depan di-mirror.
        // Ini akan membuat bounding box menempel sempurna pada wajah di preview.
        finalRect.origin.x = viewSize.width - finalRect.origin.x - finalRect.width
        
        return finalRect
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
        guard let context = modelContext, !todaysAttendedUserIDs.contains(user.id) else {
            return
        }
        
        let newRecord = AttendanceRecord(userID: user.id, userName: user.name)
        context.insert(newRecord)
        
        do {
            try context.save()
            todaysAttendedUserIDs.insert(user.id)
            
            let timeString = Date().formatted(date: .omitted, time: .standard)
            statusMessage = "✅ Absen berhasil: \(user.name) pukul \(timeString)"
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                if self.statusMessage.contains(user.name) {
                    self.statusMessage = ""
                }
            }
        } catch {
            print("Gagal menyimpan absensi: \(error)")
            statusMessage = "❌ Gagal menyimpan data absensi."
        }
    }
}

extension ScanViewModel: RealtimeCameraServiceDelegate {
    func cameraService(didDetectFaces faces: [DetectedFace], videoDimensions: CMVideoDimensions?) {
        self.videoDimensions = videoDimensions
        self.detectedFaces = faces
        
        for face in faces {
            if let user = face.recognizedUser {
                recordAttendance(for: user)
            }
        }
    }
}
