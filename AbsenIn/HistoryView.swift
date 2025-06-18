//
//  HistoryView.swift
//  AbsenIn
//
//  Created by Louis Fernando on 18/06/25.
//

import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack {
            DatePicker(
                "Pilih Tanggal",
                selection: $viewModel.selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding(.horizontal)
            
            if viewModel.recordsForSelectedDate.isEmpty {
                ContentUnavailableView(
                    "Tidak Ada Data",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Tidak ada riwayat absensi pada tanggal \(viewModel.selectedDate, formatter: itemFormatter).")
                )
            } else {
                List {
                    ForEach(viewModel.recordsForSelectedDate, id: \.timestamp) { record in
                        HStack {
                            Text(record.userName)
                                .fontWeight(.bold)
                            Spacer()
                            Text(record.timestamp, style: .time)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onAppear {
            viewModel.setup(modelContext: modelContext)
            viewModel.fetchRecords()
        }
        .onChange(of: viewModel.selectedDate) { _, _ in
            viewModel.fetchRecords()
        }
        .navigationTitle("Riwayat Presensi")
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    return formatter
}()
