import Foundation
import SwiftData
import SwiftUI

struct AttendanceStat: Identifiable {
    let id = UUID(); let date: Date; let count: Int
    var dayInitial: String { let f = DateFormatter(); f.dateFormat = "E"; return f.string(from: date) }
}
@MainActor
class HistoryViewModel: ObservableObject {
    @Published var weeklyStats: [AttendanceStat] = []; @Published var selectedDate: Date = .now; @Published var recordsForSelectedDate: [AttendanceRecord] = []
    private var modelContext: ModelContext?
    func setup(modelContext: ModelContext) { self.modelContext = modelContext; fetchWeeklyStats(); fetchRecordsForSelectedDate() }
    func fetchWeeklyStats() {
        guard let context = modelContext else { return }
        var stats: [AttendanceStat] = []; let cal = Calendar.current
        for i in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let start = cal.startOfDay(for: date); guard let end = cal.date(byAdding: .day, value: 1, to: start) else { continue }
            let predicate = #Predicate<AttendanceRecord> { $0.timestamp >= start && $0.timestamp < end }
            do { let count = try context.fetchCount(FetchDescriptor(predicate: predicate)); stats.insert(.init(date: date, count: count), at: 0) }
            catch { stats.insert(.init(date: date, count: 0), at: 0) }
        }
        self.weeklyStats = stats
    }
    func fetchRecordsForSelectedDate() {
        guard let context = modelContext else { return }
        let cal = Calendar.current; let start = cal.startOfDay(for: selectedDate); guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }
        let predicate = #Predicate<AttendanceRecord> { $0.timestamp >= start && $0.timestamp < end }
        let descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        recordsForSelectedDate = (try? context.fetch(descriptor)) ?? []
    }
}
