import SwiftUI
import Charts

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @Environment(\.modelContext) private var modelContext
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                attendanceChartView.padding(.horizontal)
                Divider()
                dailyAttendanceSection.padding(.horizontal)
            }.padding(.vertical)
        }.background(Color(.systemGroupedBackground)).navigationTitle("Riwayat Presensi")
        .onAppear { viewModel.setup(modelContext: modelContext) }
        .onChange(of: viewModel.selectedDate) { viewModel.fetchRecordsForSelectedDate() }
    }
    private var attendanceChartView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Aktivitas Mingguan").font(.title2.bold())
            Text("Jumlah karyawan yang hadir dalam 7 hari terakhir.").font(.subheadline).foregroundStyle(.secondary)
            Chart(viewModel.weeklyStats) { stat in
                BarMark(x: .value("Hari", stat.dayInitial), y: .value("Jumlah Hadir", stat.count)).foregroundStyle(by: .value("Hari", stat.dayInitial)).cornerRadius(8)
            }.chartLegend(.hidden).chartYAxis { AxisMarks(values: .automatic(desiredCount: 5)) { value in AxisGridLine(); AxisTick(); if let val = value.as(Int.self) { AxisValueLabel("\(val)") } } }.frame(height: 200).padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(12)
        }
    }
    private var dailyAttendanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Detail Harian").font(.title2.bold())
            DatePicker("Pilih Tanggal", selection: $viewModel.selectedDate, displayedComponents: .date).datePickerStyle(.compact)
            if viewModel.recordsForSelectedDate.isEmpty {
                ContentUnavailableView("Tidak Ada Data", systemImage: "calendar.badge.exclamationmark").padding(.vertical, 40).background(Color(.secondarySystemGroupedBackground)).cornerRadius(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.recordsForSelectedDate) { record in
                        VStack {
                            HStack { Text(record.userName).fontWeight(.semibold); Spacer(); Text(record.timestamp, style: .time).font(.subheadline).foregroundStyle(.secondary) }.padding()
                            if record.id != viewModel.recordsForSelectedDate.last?.id { Divider().padding(.leading) }
                        }
                    }
                }.background(Color(.secondarySystemGroupedBackground)).cornerRadius(12)
            }
        }
    }
}
