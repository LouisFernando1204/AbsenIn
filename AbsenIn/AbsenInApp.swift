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

    // State to track if the user is registered. This will drive the initial view.
    @State private var isUserRegistered: Bool

    init() {
        // Initialize with a default value. The actual check will happen in onAppear of the WelcomeView
        // or a similar mechanism if we were not using @State here directly dependent on the initial check.
        // For the purpose of setting up the initial @State, we can do a quick check.
        var registered = false
        do {
            let container = try ModelContainer(for: User.self)
            let fetchDescriptor = FetchDescriptor<User>()
            let count = try container.mainContext.fetchCount(fetchDescriptor)
            registered = count > 0
        } catch {
            print("Failed to check user registration status: \(error)")
        }
        _isUserRegistered = State(initialValue: registered) // Initialize @State directly
    }

    var body: some Scene {
        WindowGroup {
            
            if isUserRegistered {
                TabBarView()
            } else {
                // If not registered, show the WelcomeView.
                // WelcomeView will handle its own navigation to RegistrationView.
                WelcomeView(isUserRegistered: $isUserRegistered)
            }
        }
        .modelContainer(for: [User.self, AttendanceRecord.self]) // Register all models here
    }
}
