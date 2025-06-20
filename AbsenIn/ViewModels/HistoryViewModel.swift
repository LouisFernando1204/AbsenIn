//
//  HistoryViewModel.swift
//  AbsenIn
//
//  Created by Louis Fernando on 18/06/25.
//

import Foundation
import SwiftData

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var selectedDate: Date = .now
    @Published var recordsForSelectedDate: [AttendanceRecord] = []
    
    private var modelContext: ModelContext?
    
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func fetchRecords() {
        guard let context = modelContext else { return }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        
        // Predikat untuk filter data berdasarkan rentang waktu satu hari
        let predicate = #Predicate<AttendanceRecord> { record in
            record.timestamp >= startOfDay && record.timestamp < endOfDay
        }
        
        // Deskriptor untuk mengambil dan mengurutkan data
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            recordsForSelectedDate = try context.fetch(descriptor)
        } catch {
            print("Gagal mengambil data riwayat: \(error)")
            recordsForSelectedDate = []
        }
    }
}
