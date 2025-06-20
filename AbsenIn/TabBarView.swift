//
//  TabBarView.swift
//  AbsenIn
//
//  Created by Samuel Miracle Kristanto on 18/06/25.
//


import SwiftUI

struct TabBarView: View {
    var body: some View {
        TabView {
            RegistrationView()
                .tabItem {
                    Label("Register", systemImage: "camera.fill")
                }

            ScanView()
                .tabItem {
                    Label("Scan", systemImage: "faceid")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }
        }
    }
}
