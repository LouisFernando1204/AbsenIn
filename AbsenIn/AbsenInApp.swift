//
//  AbsenInApp.swift
//  AbsenIn
//
//  Created by Louis Fernando on 17/06/25.
//

import SwiftUI
import SwiftData

struct AttendanceContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]

    var body: some View {
        // View ini punya akses ke environment, lalu membuat dan meneruskannya
        AttendanceView(users: users, modelContext: modelContext)
    }
}

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
            // Jika ada pengguna terdaftar, langsung ke AttendanceView
            // Jika tidak, mulai dari WelcomeView
            if isUserRegistered {
                AttendanceContainerView()
            } else {
                WelcomeView()
            }
        }
        .modelContainer(for: [User.self, AttendanceRecord.self]) // Daftarkan semua model di sini
    }
}
