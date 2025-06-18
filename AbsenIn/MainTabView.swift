//
//  MainTabView.swift
//  AbsenIn
//
//  Created by Louis Fernando on 18/06/25.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            // Tab 1: Pendaftaran Wajah
            // NavigationStack membungkus RegistrationView
            NavigationStack {
                RegistrationView()
            }
            .tabItem { // <-- PASTIKAN INI ADA
                Label("Register", systemImage: "person.badge.plus")
            }
            
            // Tab 2: Scan untuk Presensi
            ScanView()
                .tabItem { // <-- PASTIKAN INI ADA
                    Label("Scan", systemImage: "camera.viewfinder")
                }
            
            // Tab 3: Riwayat Presensi
            // NavigationStack membungkus HistoryView
            NavigationStack {
                HistoryView()
            }
            .tabItem { // <-- PASTIKAN INI ADA
                Label("History", systemImage: "list.bullet.clipboard")
            }
        }
    }
}
