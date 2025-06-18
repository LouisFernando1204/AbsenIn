//
//  MainView.swift
//  AbsenIn
//
//  Created by Hayya U on 17/06/25.
//

import SwiftUI

// Enum to represent tabs
enum Tab {
    case register
    case attendance
    case history
}

struct MainView: View {
    
    // 1. Pindahkan @StateObject ke view utama ini.
    // MainView sekarang yang "memiliki" dan mengontrol CameraService.
    @StateObject private var camera_service = CameraService()
    
    // 2. State untuk melacak tab yang sedang aktif.
    @State private var selected_tab: Tab = .register
    
    var body: some View {
        TabView(selection: $selected_tab) {
            
            CameraView(camera_service: camera_service)
                .tabItem {
                    Image(systemName: "person.fill.badge.plus")
                    Text("Register")
                }
                .tag(Tab.register)
            
            AttendanceView()
                .tabItem {
                    Image(systemName: "camera.fill")
                    Text("Attendance")
                }
                .tag(Tab.attendance)
    
        }
        // 4. INI BAGIAN PALING PENTING: Monitor perubahan tab
        .onChange(of: selected_tab) { newTab in
            if newTab == .register {
                camera_service.startSession() // Nyalakan kamera saat tab kamera dipilih
            } else {
                camera_service.stopSession() // Matikan kamera saat beralih ke tab lain
            }
        }
        .onAppear {
            // Saat view pertama kali muncul, jika tab default adalah kamera, nyalakan session.
            if selected_tab == .register {
                camera_service.startSession()
            }
        }
    }
}

#Preview {
    MainView()
}
