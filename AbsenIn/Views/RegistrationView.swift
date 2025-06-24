import SwiftUI
import SwiftData
import Vision

struct RegistrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \User.name) private var users: [User]
    @State private var isShowingRegistrationSheet = false
    var body: some View {
        VStack {
            if users.isEmpty {
                ContentUnavailableView("Belum Ada Pengguna", systemImage: "person.3.sequence")
            } else {
                List { ForEach(users) { user in Text(user.name) }.onDelete(perform: deleteUser) }
            }
        }.navigationTitle("Pengguna Terdaftar")
        .toolbar { Button(action: { isShowingRegistrationSheet = true }) { Image(systemName: "plus.circle.fill") } }
        .sheet(isPresented: $isShowingRegistrationSheet) { PhotoRegistrationFlowView { isShowingRegistrationSheet = false } }
    }
    private func deleteUser(at offsets: IndexSet) { for index in offsets { modelContext.delete(users[index]) } }
}

struct PhotoRegistrationFlowView: View {
    @State private var userName: String = ""
    @State private var didSubmitName = false
    var onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            EnterNameView(userName: $userName, didSubmitName: $didSubmitName)
                .navigationDestination(isPresented: $didSubmitName) {
                    PhotoTakingView(userName: userName, onFinished: onComplete)
                }
        }.toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Batal") { dismiss() } } }
    }
}

struct EnterNameView: View {
    @Binding var userName: String; @Binding var didSubmitName: Bool
    var body: some View {
        VStack(spacing: 20) {
            Spacer(); Image(systemName: "person.text.rectangle").font(.system(size: 60)).foregroundColor(.accentColor)
            Text("Registrasi Karyawan").font(.largeTitle).fontWeight(.bold)
            Text("Masukkan nama lengkap untuk memulai.").font(.subheadline).foregroundColor(.secondary).padding(.horizontal)
            TextField("Nama Lengkap", text: $userName).textFieldStyle(.roundedBorder).padding(.horizontal, 40)
            Spacer()
            Button("Lanjut") { didSubmitName = true }.buttonStyle(.borderedProminent).disabled(userName.isEmpty)
        }.padding().navigationTitle("Langkah 1: Nama").navigationBarTitleDisplayMode(.inline)
    }
}
