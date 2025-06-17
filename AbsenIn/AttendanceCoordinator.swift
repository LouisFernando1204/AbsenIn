//
//  AttendanceCoordinator.swift
//  AbsenIn
//
//  Created by Louis Fernando on 17/06/25.
//

import SwiftUI
import SwiftData

class AttendanceCoordinator: ObservableObject, FaceRecognitionDelegate {
    
    @Published var recognitionStatus: String = "Arahkan wajah ke kamera"
    @Published var statusColor: Color = .primary
    
    private var modelContext: ModelContext
    
    // State untuk menyimpan nama yang sedang ditampilkan
    // Ini membantu kita mereset UI dengan benar
    private var lastRecognizedUserName: String?
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - FaceRecognitionDelegate Conformance
    
    func didRecognize(users: [User]) {
        // Ambil user pertama saja untuk ditampilkan di UI.
        // Jika Anda ingin menampilkan banyak nama, modifikasi UI di sini.
        guard let firstUser = users.first else { return }
        
        // Langsung catat kehadiran untuk user yang terdeteksi
        recordAttendance(for: firstUser)
    }
    
    func didFailToRecognize() {
        // Jika UI sedang menampilkan pesan sukses, JANGAN ubah.
        // Biarkan pesan sukses ditampilkan selama beberapa saat.
        // Jika tidak, tampilkan pesan gagal.
        if self.statusColor != .green {
            self.recognitionStatus = "Wajah tidak dikenali. Coba lagi."
            self.statusColor = .red
            self.lastRecognizedUserName = nil // Reset nama yang dikenali
        }
    }
    
    private func recordAttendance(for user: User) {
        // Cek apakah orang yang sama baru saja dikenali.
        // Ini mencegah UI berkedip jika didRecognize terpanggil lagi dengan cepat.
        guard self.lastRecognizedUserName != user.name else { return }
        
        // Simpan nama user yang berhasil dikenali
        self.lastRecognizedUserName = user.name
        
        let newRecord = AttendanceRecord(userID: user.id, userName: user.name)
        modelContext.insert(newRecord)
        
        do {
            try modelContext.save()
            
            // Update UI untuk menampilkan pesan sukses
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeString = formatter.string(from: Date())
            
            recognitionStatus = "Halo, \(user.name)! Kehadiran berhasil dicatat pada pukul \(timeString)."
            statusColor = .green
            
            // RESET UI SETELAH JEDA SINGKAT
            // Ini adalah cara yang lebih baik daripada cooldown 5 detik yang memblokir.
            // Setelah 2-3 detik, UI akan siap untuk mengenali lagi.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                // Hanya reset jika nama yang dikenali masih sama dengan yang tadi.
                // Ini mencegah bug jika orang lain sudah dikenali dalam 3 detik ini.
                if self.lastRecognizedUserName == user.name {
                    self.recognitionStatus = "Arahkan wajah ke kamera"
                    self.statusColor = .primary
                    self.lastRecognizedUserName = nil
                }
            }
        } catch {
            recognitionStatus = "Gagal menyimpan data."
            statusColor = .red
            lastRecognizedUserName = nil
            print("Error saving attendance: \(error)")
        }
    }
}
