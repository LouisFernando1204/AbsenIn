import SwiftUI

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
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 80)).foregroundColor(.green)
                    Text(viewModel.statusMessage).font(.largeTitle.bold())
                    Spacer()
                }
            } else {
                ZStack {
                    // The preview now comes from the shared RealtimeCameraService
                    CameraPreview(session: viewModel.cameraService.session)
                        .ignoresSafeArea()
                    
                    // The bounding box must be flipped horizontally to match the mirrored live preview
                    BoundingBoxView(
                        faceObservation: viewModel.faceObservation,
                        isMatch: false
                    )
                    .scaleEffect(x: -1, y: 1, anchor: .center)
                    
                    VStack {
                        Text(viewModel.statusMessage)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(15)
                            .animation(.easeInOut, value: viewModel.statusMessage)
                        
                        Spacer()
                        
                        // The button now calls the new registration attempt method
                        Button(action: {
                            viewModel.attemptRegistration()
                        }) {
                            ZStack {
                                Circle().fill(Color.white).frame(width: 70, height: 70)
                                Circle().stroke(Color.white, lineWidth: 4).frame(width: 80, height: 80)
                            }
                        }
                    }.padding(.vertical, 40)
                }
            }
        }
        .navigationTitle("Ambil Foto")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Set the dependencies and start the camera when the view appears
            viewModel.setDependencies(context: modelContext, onComplete: onFinished)
            viewModel.start()
        }
        .onDisappear {
            // Stop the camera when the view disappears
            viewModel.stop()
        }
    }
}
