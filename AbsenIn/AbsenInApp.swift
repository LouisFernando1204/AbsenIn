//
//  AbsenInApp.swift
//  AbsenIn
//
//  Created by Louis Fernando on 17/06/25.
//

import SwiftUI
import SwiftData

@main
struct AbsenInApp: App {
    
    // Cek apakah ada pengguna yang sudah terdaftar
    private let isUserRegistered: Bool
    
    init() {
        // Cara sederhana untuk mengecek. Untuk aplikasi production, ini bisa lebih canggih.
        let container = try! ModelContainer(for: User.self)
        let fetchDescriptor = FetchDescriptor<User>()
        let count = try! container.mainContext.fetchCount(fetchDescriptor)
        isUserRegistered = count > 0
    }

    var body: some Scene {
        WindowGroup {
            MainView(isUserRegistered: isUserRegistered)
        }
        .modelContainer(for: [User.self, AttendanceRecord.self]) // Daftarkan semua model di sini
    }
}
