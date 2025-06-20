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
    var body: some View {
        NavigationStack(path: $path) {
            EnterNameView { name in path.append(name) }
            .navigationDestination(for: String.self) { name in
                PhotoTakingView(userName: name, onFinished: onComplete)
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
            Text("Siapa Nama Anda?").font(.largeTitle).fontWeight(.bold)
            Text("Masukkan nama lengkap Anda untuk memulai proses pendaftaran wajah.").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            TextField("Nama Lengkap", text: $userName).textFieldStyle(RoundedBorderTextFieldStyle()).padding(.horizontal, 40).submitLabel(.done)
            Spacer()
            Button("Lanjut") { onNameSubmitted(userName) }.font(.headline).padding().frame(maxWidth: .infinity).background(userName.isEmpty ? Color.gray : Color.blue).foregroundColor(.white).cornerRadius(10).padding(.horizontal).disabled(userName.isEmpty)
        }
        .padding().navigationTitle("Langkah 1: Nama").navigationBarTitleDisplayMode(.inline)
        // THE FIX: This prevents the keyboard layout constraint errors.
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
                    // THE FIX: Use the new, unified CameraPreview.
                    CameraPreview(session: viewModel.photoService.session)
                        .ignoresSafeArea()
                        .onAppear { viewModel.photoService.startRunning() }
                        .onDisappear { viewModel.photoService.stopRunning() }
                    VStack {
                        InstructionView(instruction: viewModel.currentInstruction, status: viewModel.statusMessage)
                        Spacer()
                        ProgressIndicatorView(totalPoses: viewModel.totalPoses, currentPoseIndex: viewModel.currentPoseIndex, photosForCurrentPose: viewModel.photosForCurrentPoseCount)
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
    
    struct ProgressIndicatorView: View {
        let totalPoses: Int
        let currentPoseIndex: Int
        let photosForCurrentPose: Int
        var body: some View {
            VStack(spacing: 15) {
                Text("Pose \(min(currentPoseIndex + 1, totalPoses)) dari \(totalPoses)")
                    .font(.headline).foregroundColor(.white)
                HStack(spacing: 10) {
                    ForEach(0..<5) { index in
                        Circle().fill(index < photosForCurrentPose ? Color.green : Color.white.opacity(0.5)).frame(width: 15, height: 15)
                    }
                }
                .animation(.default, value: photosForCurrentPose)
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

// MARK: - Photo Registration ViewModel
@MainActor
class PhotoRegistrationViewModel: ObservableObject {
    enum Pose: CaseIterable {
        case center, left, right, up, down
        var instruction: String {
            switch self {
            case .center: return "Lihat lurus ke depan dan tahan"
            case .left: return "Lihat ke kiri dan tahan"
            case .right: return "Lihat ke kanan dan tahan"
            case .up: return "Lihat ke atas dan tahan"
            case .down: return "Lihat ke bawah dan tahan"
            }
        }
    }
    
    @Published var currentPoseIndex = 0
    @Published var photosForCurrentPoseCount = 0
    @Published var isFinished = false
    @Published var statusMessage = ""
    let photoService = PhotoCaptureService()
    private let userName: String
    private var captureTimer: Timer?
    private var capturedPrints: [VNFeaturePrintObservation] = []
    private var centralLandmarks: VNFaceLandmarks2D?
    private var isWaitingForNextPose = false
    var totalPoses: Int { Pose.allCases.count }
    var currentInstruction: String {
        guard currentPoseIndex < Pose.allCases.count else { return "Selesai!" }
        return Pose.allCases[currentPoseIndex].instruction
    }

    init(userName: String) { self.userName = userName }

    func startRegistration() {
        statusMessage = "Bersiap..."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.startNextPose() }
    }
    
    private func startNextPose() {
        guard currentPoseIndex < totalPoses else {
            if !isFinished { isFinished = true }
            return
        }
        photosForCurrentPoseCount = 0
        isWaitingForNextPose = false
        statusMessage = "Tahan posisi..."
        
        captureTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            // CONCURRENCY FIX: Ensure the call to the main actor method is done safely.
            DispatchQueue.main.async {
                self?.captureAndProcessPhoto()
            }
        }
    }

    private func captureAndProcessPhoto() {
        guard !isWaitingForNextPose else { return }
        photoService.capturePhoto { [weak self] image in
            guard let self = self, let image = image else { return }
            self.processImage(image)
        }
    }

    private func processImage(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let faceRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self, let results = request.results as? [VNFaceObservation], !results.isEmpty else { return }
            self.extractFeatures(from: cgImage)
        }
        try? requestHandler.perform([faceRequest])
    }

    private func extractFeatures(from image: CGImage) {
        let featureRequest = VNGenerateImageFeaturePrintRequest()
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        
        do {
            let requestHandler = VNImageRequestHandler(cgImage: image, options: [:])
            try requestHandler.perform([featureRequest, landmarksRequest])
            
            guard let featurePrint = featureRequest.results?.first as? VNFeaturePrintObservation,
                  let landmarks = landmarksRequest.results?.first as? VNFaceObservation,
                  let faceLandmarks = landmarks.landmarks else { return }

            DispatchQueue.main.async {
                guard !self.isWaitingForNextPose else { return }
                self.capturedPrints.append(featurePrint)
                self.photosForCurrentPoseCount += 1
                
                if Pose.allCases[self.currentPoseIndex] == .center && self.centralLandmarks == nil {
                    self.centralLandmarks = faceLandmarks
                }
                
                if self.photosForCurrentPoseCount >= 5 {
                    self.isWaitingForNextPose = true
                    self.captureTimer?.invalidate()
                    self.currentPoseIndex += 1
                    
                    if self.currentPoseIndex >= self.totalPoses {
                        self.statusMessage = "Semua foto berhasil diambil!"
                        if !self.isFinished { self.isFinished = true }
                    } else {
                        self.statusMessage = "Bagus! Siap untuk pose berikutnya..."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.startNextPose() }
                    }
                }
            }
        } catch { /* Ignore frames that fail processing */ }
    }

    func saveUser(context: ModelContext, completion: @escaping () -> Void) {
        guard !capturedPrints.isEmpty, let landmarks = centralLandmarks else {
            print("Data registrasi tidak lengkap."); completion(); return
        }
        do {
            let featureprintData = try NSKeyedArchiver.archivedData(withRootObject: capturedPrints, requiringSecureCoding: true)
            let landmarkData = try NSKeyedArchiver.archivedData(withRootObject: landmarks, requiringSecureCoding: true)
            let newUser = User(name: userName, faceprintData: featureprintData, faceLandmarksData: landmarkData)
            context.insert(newUser)
            try context.save()
            print("Pengguna baru berhasil disimpan: \(userName)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { completion() }
        } catch {
            print("Gagal menyimpan pengguna: \(error)"); completion()
        }
    }
}
