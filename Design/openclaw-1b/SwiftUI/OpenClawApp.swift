import SwiftUI

@main
struct OpenClawApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

enum AppTab: Hashable { case home, chats, skills, activity, compose }

struct RootView: View {
    @State private var tab: AppTab = .home
    @State private var lastTab: AppTab = .home
    @State private var showCompose = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: .home) {
                NavigationStack { HomeView() }
            }
            Tab("Chats", systemImage: "bubble.left", value: .chats) {
                NavigationStack { ConversationListView() }
            }
            Tab("Skills", systemImage: "square.grid.2x2", value: .skills) {
                NavigationStack { SkillsView() }
            }
            Tab("Activity", systemImage: "waveform.path.ecg", value: .activity) {
                NavigationStack { ActivityView() }
            }
            // iOS 26 draws the .search role as a detached glass circle — used here as Compose.
            Tab(value: .compose, role: .search) {
                Color.clear
            } label: {
                Label("New Chat", systemImage: "square.and.pencil")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: tab) { old, new in
            if new == .compose { showCompose = true; tab = old } else { lastTab = new }
        }
        .sheet(isPresented: $showCompose) {
            NavigationStack { ChatView(conversation: .empty) }
        }
    }
}

struct ConversationListView: View {
    var body: some View {
        List(MockData.conversations) { c in
            NavigationLink(value: c) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(c.updatedLabel).font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                }
            }
            .listRowBackground(Color.white.opacity(0.06))
        }
        .scrollContentBackground(.hidden)
        .background(AmbientGlow())
        .navigationTitle("Chats")
        .navigationDestination(for: Conversation.self) { ChatView(conversation: $0) }
    }
}
