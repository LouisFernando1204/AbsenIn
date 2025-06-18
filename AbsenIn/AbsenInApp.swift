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
    var body: some Scene {
        WindowGroup {
            MainTabView() // Langsung tampilkan MainTabView sebagai view utama
        }
        // Daftarkan semua model yang akan digunakan aplikasi di sini
        .modelContainer(for: [User.self, AttendanceRecord.self])
    }
}
