import Foundation
import SwiftData
import SwiftUI // Import SwiftUI untuk Color

// Struct untuk merepresentasikan satu bar di dalam grafik
struct AttendanceStat: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
    
    // Properti untuk label di grafik
    var dayInitial: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E" // "E" untuk hari (Sen, Sel, Rab)
        return formatter.string(from: date)
    }
}

@MainActor
class HistoryViewModel: ObservableObject {
    // Data untuk Grafik
    @Published var weeklyStats: [AttendanceStat] = []
    
    // Data untuk Daftar Harian
    @Published var selectedDate: Date = .now
    @Published var recordsForSelectedDate: [AttendanceRecord] = []
    
    private var modelContext: ModelContext?
    
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Saat pertama kali setup, langsung ambil semua data yang diperlukan
        fetchWeeklyStats()
        fetchRecordsForSelectedDate()
    }
    
    // Mengambil data untuk grafik 7 hari terakhir
    func fetchWeeklyStats() {
        guard let context = modelContext else { return }
        
        var stats: [AttendanceStat] = []
        let calendar = Calendar.current
        
        // Loop untuk 7 hari ke belakang, dari hari ini
        for i in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -i, to: Date()) else { continue }
            
            let startOfDay = calendar.startOfDay(for: date)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { continue }
            
            let predicate = #Predicate<AttendanceRecord> { record in
                record.timestamp >= startOfDay && record.timestamp < endOfDay
            }
            
            // Kita hanya butuh jumlahnya, jadi fetch descriptor lebih sederhana
            let descriptor = FetchDescriptor(predicate: predicate)
            
            do {
                let count = try context.fetchCount(descriptor)
                // Masukkan ke awal array agar urutannya benar (dari 6 hari lalu ke hari ini)
                stats.insert(AttendanceStat(date: date, count: count), at: 0)
            } catch {
                print("Gagal mengambil data statistik untuk tanggal \(date): \(error)")
                stats.insert(AttendanceStat(date: date, count: 0), at: 0)
            }
        }
        
        self.weeklyStats = stats
    }
    
    // Mengambil data untuk daftar absensi pada tanggal yang dipilih
    func fetchRecordsForSelectedDate() {
        guard let context = modelContext else { return }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        
        let predicate = #Predicate<AttendanceRecord> { record in
            record.timestamp >= startOfDay && record.timestamp < endOfDay
        }
        
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
