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
            MainTabView() // No modifier needed here anymore
        }
        .modelContainer(for: [User.self, AttendanceRecord.self])
    }
}
