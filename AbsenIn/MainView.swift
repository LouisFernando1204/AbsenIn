//
//  MainView.swift
//  AbsenIn
//
//  Created by Hayya U on 17/06/25.
//

import SwiftUI
import SwiftData

enum Tab: Hashable {
    case register
    case attendance
}

struct MainView: View {
    let isUserRegistered: Bool
    
    @Environment(\.modelContext) var modelContext
    @Query var users: [User]
    @State private var selectedTab: Tab = .attendance

    var body: some View {
        if isUserRegistered {
            TabView(selection: $selectedTab) {
                RegistrationView()
                    .tabItem {
                        Image(systemName: "person.fill.badge.plus")
                        Text("Register")
                    }
                    .tag(Tab.register)
                
                AttendanceView(users: users, modelContext: modelContext)
                    .tabItem {
                        Image(systemName: "camera.fill")
                        Text("Attendance")
                    }
                    .tag(Tab.attendance)
            }
        } else {
            WelcomeView()
        }
    }
}
