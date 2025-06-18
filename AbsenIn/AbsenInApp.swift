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
    @State private var isUserRegistered: Bool
    private let sharedModelContainer: ModelContainer

    init() {
        var registered = false
        var tempContainer: ModelContainer!

        do {
            let schema = Schema([User.self, AttendanceRecord.self])
            let config = ModelConfiguration("AbsenInModel") // beri nama yang konsisten
            tempContainer = try ModelContainer(for: schema, configurations: [config])
            let fetchDescriptor = FetchDescriptor<User>()
            let count = try tempContainer.mainContext.fetchCount(fetchDescriptor)
            registered = count > 0
        } catch {
            print("Failed to initialize model container or fetch user count: \(error)")
        }

        self.sharedModelContainer = tempContainer
        _isUserRegistered = State(initialValue: registered)
    }

    var body: some Scene {
        WindowGroup {
            if isUserRegistered {
                TabBarView()
                    .modelContainer(sharedModelContainer)
            } else {
                WelcomeView(isUserRegistered: $isUserRegistered)
                    .modelContainer(sharedModelContainer)
            }
        }
    }
}
