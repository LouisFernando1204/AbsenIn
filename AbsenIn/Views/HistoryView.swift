import SwiftUI
import Charts // Jangan lupa import Charts

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        // Gunakan ScrollView agar bisa di-scroll di layar kecil
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // --- BAGIAN GRAFIK (SPOTLIGHT) ---
                attendanceChartView
                    .padding(.horizontal)
                
                Divider()
                
                // --- BAGIAN DAFTAR HARIAN ---
                dailyAttendanceSection
                    .padding(.horizontal)
                
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground)) // Latar belakang yang sesuai HIG
        .navigationTitle("Riwayat Presensi")
        .onAppear {
            viewModel.setup(modelContext: modelContext)
        }
        .onChange(of: viewModel.selectedDate) {
            viewModel.fetchRecordsForSelectedDate()
        }
    }
    
    // View untuk Grafik Absensi Mingguan
    private var attendanceChartView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Aktivitas Mingguan")
                .font(.title2.bold())
                .foregroundStyle(.primary)
            
            Text("Jumlah karyawan yang hadir dalam 7 hari terakhir.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // Chart View
            Chart(viewModel.weeklyStats) { stat in
                BarMark(
                    x: .value("Hari", stat.dayInitial),
                    y: .value("Jumlah Hadir", stat.count)
                )
                .foregroundStyle(by: .value("Hari", stat.dayInitial))
                .cornerRadius(8)
            }
            .chartLegend(.hidden) // Sembunyikan legenda agar lebih bersih
            .chartYAxis {
                // Pastikan sumbu Y hanya menampilkan angka bulat
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisTick()
                    if let intValue = value.as(Int.self) {
                        AxisValueLabel("\(intValue)")
                    }
                }
            }
            .frame(height: 200)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
    
    // View untuk Daftar Absensi Harian dan Pemilih Tanggal
    private var dailyAttendanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Detail Harian")
                .font(.title2.bold())
            
            // DatePicker sekarang lebih ringkas
            DatePicker(
                "Pilih Tanggal",
                selection: $viewModel.selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            
            // Daftar atau pesan "Tidak Ada Data"
            if viewModel.recordsForSelectedDate.isEmpty {
                ContentUnavailableView(
                    "Tidak Ada Data",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Tidak ada riwayat absensi pada tanggal yang dipilih.")
                )
                .padding(.vertical, 40)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            } else {
                // Gunakan VStack untuk tampilan yang lebih custom daripada List
                VStack(spacing: 0) {
                    ForEach(viewModel.recordsForSelectedDate, id: \.timestamp) { record in
                        VStack {
                            HStack {
                                Text(record.userName)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(record.timestamp, style: .time)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            
                            // Tambahkan Divider kecuali untuk item terakhir
                            if record.timestamp != viewModel.recordsForSelectedDate.last?.timestamp {
                                Divider().padding(.leading)
                            }
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
    }
}

// Preview untuk memudahkan desain
#Preview {
    NavigationStack {
        HistoryView()
    }
}
