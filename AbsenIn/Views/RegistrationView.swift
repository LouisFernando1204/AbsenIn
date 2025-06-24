import SwiftUI
import Vision
import SwiftData

struct RegistrationView: View {
    @Environment(\.modelContext) private var modelContext
    
    // Sort by the newest date on top
    @Query(sort: \User.registrationDate, order: .reverse) private var employees: [User]
    
    @State private var isShowingRegistrationSheet = false
    
    var body: some View {
        NavigationStack {
            Group {
                if employees.isEmpty {
                    ContentUnavailableView(
                        "Belum Ada Karyawan",
                        systemImage: "person.3.sequence",
                        description: Text("Tekan tombol '+' untuk mendaftarkan karyawan pertama.")
                    )
                } else {
                    List {
                        ForEach(employees) { employee in
                            EmployeeRowView(employee: employee) {
                                // This is the delete action that gets passed
                                delete(employee)
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                        // .onDelete is no longer needed here
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Daftar Karyawan")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isShowingRegistrationSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $isShowingRegistrationSheet) {
                PhotoRegistrationFlowView { isShowingRegistrationSheet = false }
            }
        }
    }
    
    // The new delete function takes a User object directly
    private func delete(_ employee: User) {
        modelContext.delete(employee)
    }
}

struct EmployeeRowView: View {
    let employee: User
    var onDelete: () -> Void // The delete action closure
    
    // Formatter for a clean date string
    private var registrationDateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long // e.g., "July 14, 2024"
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "id_ID") // Indonesian date format
        return formatter.string(from: employee.registrationDate)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.accentColor.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(employee.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Terdaftar: \(registrationDateFormatted)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(uiColor: .systemGray6))
        .cornerRadius(12)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                // Call the onDelete closure passed from the parent view
                onDelete()
            } label: {
                Label("Hapus", systemImage: "trash.fill")
            }
            .tint(.red) // This colors the button
        }
    }
}


// MARK: - Registration Flow Manager
struct PhotoRegistrationFlowView: View {
    @State private var path = NavigationPath()
    var onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            EnterNameView { name in path.append(name) }
            .navigationDestination(for: String.self) { name in
                PhotoTakingView(userName: name, onFinished: onComplete)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) { Image(systemName: "xmark") }
            }
        }
    }
}

// MARK: - Step 1: Enter Name
struct EnterNameView: View {
    @State private var userName: String = ""
    var onNameSubmitted: (String) -> Void
    var body: some View {
        VStack(spacing: 20) {
            Spacer(); Image(systemName: "person.text.rectangle").font(.system(size: 60)).foregroundColor(.accentColor)
            Text("Registrasi Karyawan").font(.largeTitle).fontWeight(.bold)
            Text("Masukkan nama lengkap Anda untuk memulai proses pendaftaran wajah.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            TextField("Nama Lengkap", text: $userName).textFieldStyle(RoundedBorderTextFieldStyle()).padding(.horizontal, 40).submitLabel(.done)
            Spacer()
            Button("Lanjut") { onNameSubmitted(userName) }.font(.headline).padding().frame(maxWidth: .infinity).background(userName.isEmpty ? Color.gray : Color.blue).foregroundColor(.white).cornerRadius(10).padding(.horizontal).disabled(userName.isEmpty)
        }
        .padding().navigationTitle("Langkah 1: Nama").navigationBarTitleDisplayMode(.inline).ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// MARK: - Step 2: Automatic Photo Taking View
struct PhotoTakingView: View {
    let userName: String
    var onFinished: () -> Void
    @StateObject private var viewModel: PhotoRegistrationViewModel
    @Environment(\.modelContext) private var modelContext

    init(userName: String, onFinished: @escaping () -> Void) {
        self.userName = userName
        self.onFinished = onFinished
        _viewModel = StateObject(wrappedValue: PhotoRegistrationViewModel(userName: userName))
    }

    var body: some View {
        VStack {
            if viewModel.isFinished {
                SavingView()
            } else {
                ZStack {
                    CameraPreview(session: viewModel.photoService.session, videoDevice: viewModel.photoService.videoDevice)
                        .ignoresSafeArea()
                        .onAppear { viewModel.startRegistration() }
                        .onDisappear { viewModel.photoService.stopRunning() }

                    VStack {
                        InstructionView(
                            instruction: viewModel.currentInstructionText,
                            symbolName: viewModel.currentInstructionSymbol,
                            status: viewModel.statusMessage
                        )
                        Spacer()
                        ProgressViewSection(
                            count: viewModel.photosCapturedCount,
                            total: viewModel.totalPhotosToCapture
                        )
                    }
                    .padding(.vertical, 40)
                }
            }
        }
        .navigationTitle("Pendaftaran Wajah")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onReceive(viewModel.$isFinished) { finished in
            if finished { viewModel.saveUser(context: modelContext, completion: onFinished) }
        }
    }
    
    struct InstructionView: View {
        let instruction: String, symbolName: String, status: String
        var body: some View {
            VStack(spacing: 8) {
                Image(systemName: symbolName).font(.system(size: 50, weight: .light)).foregroundColor(.white).padding(.bottom, 5)
                Text(instruction).font(.title2).fontWeight(.bold)
                Text(status).font(.subheadline).opacity(status.isEmpty ? 0 : 1).animation(.easeInOut, value: status)
            }
            .foregroundColor(.white).padding().background(Color.black.opacity(0.7)).cornerRadius(15).animation(.easeInOut, value: instruction)
        }
    }

    struct ProgressViewSection: View {
        let count: Int, total: Int
        var body: some View {
            VStack(spacing: 15) {
                Text("Mengambil foto \(count) dari \(total)").font(.headline).foregroundColor(.white)
                ProgressView(value: Float(count), total: Float(total)).progressViewStyle(LinearProgressViewStyle(tint: .green)).frame(width: 200)
            }
            .padding().background(Color.black.opacity(0.6)).cornerRadius(10)
        }
    }

    struct SavingView: View {
        var body: some View {
            VStack(spacing: 20) {
                Spacer(); ProgressView(); Text("Menyimpan data, mohon tunggu...").font(.headline); Spacer()
            }
        }
    }
}
