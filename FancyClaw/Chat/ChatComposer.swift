import AVFoundation
import ChatCore
import GatewayProtocol
import OSLog
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ChatComposer: View {
    let isStreaming: Bool
    @Binding var attachments: [PreparedAttachment]
    let limits: () async -> HelloOK.AttachmentLimits?
    let send: (String, [PreparedAttachment]) async -> Bool
    let stop: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @State private var sentCount = 0
    @State private var stopCount = 0
    @State private var draft = ""
    @FocusState private var isMessageFocused: Bool
    private static let focusLogger = Logger(subsystem: "FancyClaw", category: "ComposerFocus")
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var showingCamera = false
    @State private var isPreparing = false
    @State private var isSubmitting = false
    @State private var attachmentError: String?
    @State private var importTask: Task<Void, Never>?
    @State private var pipeline = AttachmentPipeline()

    var body: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                AttachmentTray(attachments: attachments, remove: { id in
                    attachments.removeAll { $0.id == id }
                })
                .disabled(isSubmitting)
                .padding(.horizontal, 8)
            }
            if isPreparing {
                HStack { ProgressView(); Text("Preparing attachment…").font(.subheadline) }
            }
            HStack(alignment: .bottom, spacing: 6) {
                Menu {
                    Button("Photo Library", systemImage: "photo.on.rectangle") { showingPhotos = true }
                    Button("Take Photo", systemImage: "camera") { openCamera() }
                    Button("Choose File", systemImage: "doc") { showingFiles = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Attach")
                .disabled(isPreparing || isSubmitting)
                .accessibilityIdentifier("chat.attach")

                TextField("Message FancyClaw", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isMessageFocused)
                    .frame(minHeight: 44)
                    .disabled(isSubmitting)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .accessibilityIdentifier("chat.composer")

                Button(isStreaming ? "Stop" : "Send",
                       systemImage: isStreaming ? "stop.fill" : "arrow.up") {
                    if isStreaming { stopWithFeedback() } else { submit() }
                }
                    .labelStyle(.iconOnly)
                    .buttonStyle(ChatComposerButtonStyle(role: isStreaming ? .stop : .send, reduceMotion: reduceMotion))
                    .disabled(!isStreaming && (isPreparing || isSubmitting || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)))
                    .accessibilityIdentifier(isStreaming ? "chat.stop" : "chat.send")
                    .accessibilityInputLabels(isStreaming ? ["Stop response", "Stop generating"] : ["Send message"])
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background {
            // The background receives padding and gap taps without taking taps from controls.
            Color.clear
                .contentShape(.rect(cornerRadius: 28))
                .onTapGesture {
                    guard !isSubmitting else { return }
                    Self.focusLogger.debug("Composer background tapped; requesting focus")
                    isMessageFocused = true
                }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .photosPicker(isPresented: $showingPhotos, selection: $selectedPhotos, matching: .images)
        .onChange(of: selectedPhotos) { _, photos in
            guard !photos.isEmpty else { return }
            preparePhotos(photos)
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): prepareFiles(urls)
            case .failure(let error): attachmentError = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            AttachmentCamera { result in
                showingCamera = false
                if let result {
                    switch result {
                    case .success(let data): prepareCamera(data)
                    case .failure(let error): attachmentError = error.localizedDescription
                    }
                }
            }
            .ignoresSafeArea()
        }
        .alert("Attachment unavailable", isPresented: hasAttachmentError) {
            Button("OK") { attachmentError = nil }
        } message: { Text(attachmentError ?? "") }
        .onChange(of: isMessageFocused) { _, focused in
            Self.focusLogger.debug("Message field focused: \(focused)")
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardWillShowNotification) {
                Self.focusLogger.debug("Keyboard will show")
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardDidShowNotification) {
                Self.focusLogger.debug("Keyboard did show")
            }
        }
        .onDisappear { importTask?.cancel() }
        .sensoryFeedback(.success, trigger: sentCount) { _, _ in hapticsEnabled }
        .sensoryFeedback(.impact(weight: .light), trigger: stopCount) { _, _ in hapticsEnabled }
        .sensoryFeedback(.error, trigger: attachmentError) { (_: String?, value: String?) in hapticsEnabled && value != nil }
    }

    private var hasAttachmentError: Binding<Bool> {
        Binding(get: { attachmentError != nil }, set: { if !$0 { attachmentError = nil } })
    }

    private func stopWithFeedback() {
        stopCount += 1
        stop()
    }

    private func submit() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming, !isPreparing, !isSubmitting, !message.isEmpty || !attachments.isEmpty else { return }
        let uploads = attachments
        isSubmitting = true
        Task {
            if await send(message, uploads) {
                sentCount += 1
                draft = ""
                attachments.removeAll { attachment in uploads.contains { $0.id == attachment.id } }
            }
            isSubmitting = false
        }
    }

    private func preparePhotos(_ photos: [PhotosPickerItem]) {
        isPreparing = true
        importTask = Task {
            defer { isPreparing = false; selectedPhotos = [] }
            let policy = await limits()
            for photo in photos {
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else { throw AttachmentError.invalidImage }
                    let prepared = try await pipeline.prepare(data: data, fileName: "Photo.jpg", imageRequired: true, limits: policy)
                    try Task.checkCancellation()
                    attachments.append(prepared)
                } catch is CancellationError { return }
                catch { attachmentError = error.localizedDescription }
            }
        }
    }

    private func prepareFiles(_ urls: [URL]) {
        isPreparing = true
        importTask = Task {
            defer { isPreparing = false }
            let policy = await limits()
            for url in urls {
                do {
                    let prepared = try await pipeline.prepareFile(at: url, limits: policy)
                    try Task.checkCancellation()
                    attachments.append(prepared)
                } catch is CancellationError { return }
                catch { attachmentError = error.localizedDescription }
            }
        }
    }

    private func prepareCamera(_ data: Data) {
        isPreparing = true
        importTask = Task {
            defer { isPreparing = false }
            do {
                let policy = await limits()
                let prepared = try await pipeline.prepare(data: data, fileName: "Camera.jpg", imageRequired: true, limits: policy)
                try Task.checkCancellation()
                attachments.append(prepared)
            } catch is CancellationError { }
            catch { attachmentError = error.localizedDescription }
        }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            attachmentError = "A camera is unavailable on this device. Choose a photo or file instead."
            return
        }
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            if allowed { showingCamera = true }
            else { attachmentError = "Camera access is disabled. Allow camera access for FancyClaw in Settings." }
        }
    }
}

private struct ChatComposerButtonStyle: ButtonStyle {
    enum Role: Equatable {
        case send
        case stop
    }

    let role: Role
    let reduceMotion: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(width: 32, height: 32)
            .background(role == .send ? Color.accentColor : Color.primary, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(.rect)
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.78 : 1)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
    }
}
