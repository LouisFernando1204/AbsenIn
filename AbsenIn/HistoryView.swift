//
//  HistoryView.swift
//  AbsenIn
//
//  Created by Samuel Miracle Kristanto on 18/06/25.
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \AttendanceRecord.timestamp, order: .reverse) private var attendanceRecords: [AttendanceRecord]

    var body: some View {
        NavigationView {
            List {
                if attendanceRecords.isEmpty {
                    ContentUnavailableView("No Attendance Records Yet",
                                           systemImage: "calendar.badge.exclamationmark",
                                           description: Text("Your attendance history will appear here once you've scanned your face."))
                } else {
                    ForEach(attendanceRecords) { record in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(record.userName)
                                    .font(.headline)
                                Text(record.timestamp, format: .dateTime.day().month().year().hour().minute())
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Text("Attended")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(5)
                        }
                    }
                }
            }
            .navigationTitle("Attendance History")
        }
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: AttendanceRecord.self, inMemory: true) { result in
            switch result {
            case .success(let container):
                container.mainContext.insert(AttendanceRecord(userID: UUID().uuidString, userName: "John Doe", timestamp: Date().addingTimeInterval(-3600 * 24 * 2)))
                container.mainContext.insert(AttendanceRecord(userID: UUID().uuidString, userName: "Jane Smith", timestamp: Date().addingTimeInterval(-3600 * 24 * 1)))
                container.mainContext.insert(AttendanceRecord(userID: UUID().uuidString, userName: "John Doe", timestamp: Date().addingTimeInterval(-3600 * 12)))
                container.mainContext.insert(AttendanceRecord(userID: UUID().uuidString, userName: "Jane Smith", timestamp: Date()))
            case .failure(let error):
                // Handle the error, e.g., print it or show an alert in a real app
                fatalError("Failed to create ModelContainer for preview: \(error.localizedDescription)")
            }
        }
}
