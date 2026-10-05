import AVFoundation
import ChatCore
import DesignSystem
import GatewayProtocol
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Uses the same in-memory preparation and Gateway limits as the chat composer.
struct HomeAttachmentPicker: View {
    @Binding var attachments: [PreparedAttachment]
    @Binding var isPreparing: Bool
    @Binding var errorMessage: String?
    let limits: () async -> HelloOK.AttachmentLimits?
    @Environment(\.appTheme) private var theme
    @State private var photos: [PhotosPickerItem] = []
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var showingCamera = false
    @State private var importTask: Task<Void, Never>?
    private let pipeline = AttachmentPipeline()

    var body: some View {
        Menu {
            Button("Photo Library", systemImage: "photo.on.rectangle") { showingPhotos = true }
            Button("Take Photo", systemImage: "camera") { openCamera() }
            Button("Choose File", systemImage: "doc") { showingFiles = true }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold)).foregroundStyle(theme.textPrimary.color)
                .frame(width: 44, height: 44).surface(in: .circle)
        }
        .accessibilityLabel("Attach")
        .accessibilityIdentifier("home.attach")
        .photosPicker(isPresented: $showingPhotos, selection: $photos, matching: .images)
        .onChange(of: photos) { _, selected in
            guard !selected.isEmpty else { return }
            prepare {
                let policy = await limits()
                for photo in selected {
                    guard let data = try await photo.loadTransferable(type: Data.self) else { throw AttachmentError.invalidImage }
                    let upload = try await pipeline.prepare(data: data, fileName: "Photo.jpg", imageRequired: true, limits: policy)
                    try Task.checkCancellation()
                    attachments.append(upload)
                }
                photos = []
            }
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                prepare {
                    let policy = await limits()
                    for url in urls {
                        let upload = try await pipeline.prepareFile(at: url, limits: policy)
                        try Task.checkCancellation()
                        attachments.append(upload)
                    }
                }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            AttachmentCamera { result in
                showingCamera = false
                guard let result else { return }
                switch result {
                case .success(let data):
                    prepare {
                        let upload = try await pipeline.prepare(data: data, fileName: "Camera.jpg", imageRequired: true, limits: await limits())
                        try Task.checkCancellation()
                        attachments.append(upload)
                    }
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }.ignoresSafeArea()
        }
        .onDisappear { importTask?.cancel() }
    }

    private func prepare(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isPreparing else { return }
        isPreparing = true
        importTask = Task { @MainActor in
            defer { isPreparing = false }
            do { try await operation() }
            catch is CancellationError {}
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "A camera is unavailable on this device. Choose a photo or file instead."
            return
        }
        Task {
            if await AVCaptureDevice.requestAccess(for: .video) { showingCamera = true }
            else { errorMessage = "Camera access is disabled. Allow camera access for FancyClaw in Settings." }
        }
    }
}
