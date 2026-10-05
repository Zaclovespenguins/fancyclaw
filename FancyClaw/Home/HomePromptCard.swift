import ChatCore
import DesignSystem
import GatewayProtocol
import SwiftUI

struct HomePromptCard: View {
    @Bindable var draft: HomeTaskDraft
    let models: [ModelSummary]
    let agentName: String
    let connected: Bool
    let limits: () async -> HelloOK.AttachmentLimits?
    let submit: () async -> Bool
    let edit: () -> Void
    @Environment(\.appTheme) private var theme
    @AppStorage(SettingsKeys.hapticsEnabled) private var hapticsEnabled = true
    @State private var attachmentError: String?
    @State private var isPreparingAttachment = false
    @State private var sentCount = 0
    @State private var confirmingEdit = false

    private var editable: Bool { !draft.isSubmitting && !draft.hasFrozenTask }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AgentAvatar(name: agentName, size: 26)
                Text(agentName).font(.subheadline.weight(.semibold)).foregroundStyle(theme.textPrimary.color)
            }
            TextField("", text: $draft.text,
                      prompt: Text("What should I take care of?").foregroundStyle(theme.placeholder.color), axis: .vertical)
                .font(.title2.weight(.medium))
                .foregroundStyle(theme.textPrimary.color)
                .lineLimit(2...6)
                .disabled(!editable)
                .accessibilityLabel("What should I take care of?")
                .accessibilityIdentifier("home.prompt")
            if !draft.attachments.isEmpty {
                AttachmentTray(attachments: draft.attachments, remove: editable ? { id in draft.attachments.removeAll { $0.id == id } } : nil)
            }
            if isPreparingAttachment { ProgressView("Preparing attachment…").font(.footnote) }
            HStack(spacing: 8) {
                HomeAttachmentPicker(attachments: $draft.attachments, isPreparing: $isPreparingAttachment,
                                     errorMessage: $attachmentError, limits: limits)
                    .disabled(!connected || !editable || isPreparingAttachment)
                modelMenu.disabled(!connected || !editable)
                Spacer(minLength: 0)
                Button(draft.hasFrozenTask ? "Retry task" : "Send task", systemImage: "arrow.up") {
                    Task { if await submit() { sentCount += 1 } }
                }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.bg.color)
                .frame(width: 44, height: 44)
                .background(theme.textPrimary.color, in: Circle())
                .buttonStyle(PressScale())
                .disabled(!connected || !draft.canSubmit || draft.isSubmitting || isPreparingAttachment)
                .accessibilityIdentifier("home.send")
            }
            if draft.isSubmitting { ProgressView("Starting your task…").font(.footnote) }
            if let message = draft.errorMessage {
                ErrorBanner(message: message) { draft.errorMessage = nil }
            }
            if let message = attachmentError {
                ErrorBanner(message: message) { attachmentError = nil }
            }
            if draft.hasFrozenTask && !draft.isSubmitting {
                Text("Retry sends this exact task in its original chat.")
                    .font(.footnote).foregroundStyle(theme.textSecondary.color)
                Button("Edit as a new task") { confirmingEdit = true }
                    .font(.subheadline).frame(minHeight: 44)
                    .accessibilityIdentifier("home.editNewTask")
                    .confirmationDialog("Edit as a separate task?", isPresented: $confirmingEdit, titleVisibility: .visible) {
                        Button("Edit as a new task", action: edit)
                    } message: {
                        Text("The previous task stays in Chats. It may already have reached the Gateway. Editing starts a separate task.")
                    }
            }
            if !connected {
                Text("Reconnect above to start a new task. Your draft stays here.")
                    .font(.footnote).foregroundStyle(theme.textSecondary.color)
            }
        }
        .padding(16)
        .background(theme.bg.color, in: RoundedRectangle(cornerRadius: AppTheme.Radius.promptCard))
        .glass(in: .rect(cornerRadius: AppTheme.Radius.promptCard))
        .sensoryFeedback(.success, trigger: sentCount) { _, _ in hapticsEnabled }
    }

    private var modelMenu: some View {
        Menu {
            Button { draft.selectedModelID = nil } label: {
                if draft.selectedModelID == nil { Label("Gateway default", systemImage: "checkmark") }
                else { Text("Gateway default") }
            }
            ForEach(models) { model in
                Button { draft.selectedModelID = model.selectionID } label: {
                    if draft.selectedModelID == model.selectionID { Label(model.name, systemImage: "checkmark") }
                    else { Text(model.name) }
                }
                .disabled(model.available == false)
            }
        } label: {
            HStack(spacing: 5) {
                Text(models.first { $0.selectionID == draft.selectedModelID }?.name ?? "Gateway default")
                Image(systemName: "chevron.down").accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(theme.textPrimary.color)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .surface(in: .capsule)
        }
        .accessibilityLabel("Model for the new task")
        .accessibilityIdentifier("home.model")
    }
}
