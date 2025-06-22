import SwiftUI
import Vision
import SwiftData

// MARK: - Main View (Entry Point)
struct RegistrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \User.name) private var users: [User]
    @State private var isShowingRegistrationSheet = false
    
    var body: some View {
        VStack {
            if users.isEmpty {
                ContentUnavailableView("Belum Ada Pengguna", systemImage: "person.3.sequence", description: Text("Silakan daftarkan pengguna pertama."))
            } else {
                List { ForEach(users) { user in Text(user.name) }.onDelete(perform: deleteUser) }
            }
        }
        .navigationTitle("Pengguna Terdaftar")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(action: { isShowingRegistrationSheet = true }) { Image(systemName: "plus.circle.fill") } } }
        .sheet(isPresented: $isShowingRegistrationSheet) {
            PhotoRegistrationFlowView { isShowingRegistrationSheet = false }
        }
    }
    private func deleteUser(at offsets: IndexSet) { for index in offsets { modelContext.delete(users[index]) } }
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
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                }
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
            Text("Registrasi Karyawan?").font(.largeTitle).fontWeight(.bold)
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
            if viewModel.isFinished { SavingView() }
            else {
                ZStack {
                    CameraPreview(session: viewModel.photoService.session, videoDevice: viewModel.photoService.videoDevice)
                        .ignoresSafeArea()
                        .onAppear { viewModel.photoService.startRunning() }
                        .onDisappear { viewModel.photoService.stopRunning() }
                    VStack {
                        InstructionView(instruction: viewModel.currentInstruction, status: viewModel.statusMessage)
                        Spacer()
                        // PERBAIKAN 3: Panggil ProgressIndicatorView dengan parameter yang sudah diperbarui.
                        ProgressIndicatorView(totalPoses: viewModel.totalPoses, currentPoseIndex: viewModel.currentPoseIndex)
                    }.padding(.vertical, 40)
                }
            }
        }
        .navigationTitle("Pendaftaran Wajah").navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(true)
        .onAppear { viewModel.startRegistration() }
        .onReceive(viewModel.$isFinished) { finished in
            if finished { viewModel.saveUser(context: modelContext, completion: onFinished) }
        }
    }
    
    struct InstructionView: View {
        let instruction: String
        let status: String
        var body: some View {
            VStack {
                Text(instruction).font(.title2).fontWeight(.bold)
                Text(status).font(.subheadline).opacity(status.isEmpty ? 0 : 1)
            }
            .foregroundColor(.white).padding().background(Color.black.opacity(0.6)).cornerRadius(10).animation(.easeInOut, value: status)
        }
    }
    
    // PERBAIKAN 1: Ubah total struct ProgressIndicatorView.
    struct ProgressIndicatorView: View {
        let totalPoses: Int
        let currentPoseIndex: Int
        
        var body: some View {
            VStack(spacing: 15) {
                Text("Pose \(min(currentPoseIndex + 1, totalPoses)) dari \(totalPoses)")
                    .font(.headline).foregroundColor(.white)
                
                HStack(spacing: 10) {
                    ForEach(0..<totalPoses, id: \.self) { index in
                        
                        Circle()
                            .fill(colorFor(index: index))
                            .frame(width: 15, height: 15)
                    }
                }
                .animation(.default, value: currentPoseIndex)
            }
            .padding().background(Color.black.opacity(0.6)).cornerRadius(10)
        }
        
        private func colorFor(index: Int) -> Color {
            if index <= currentPoseIndex {
                return .green
            } else {
                return Color.gray
            }
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
