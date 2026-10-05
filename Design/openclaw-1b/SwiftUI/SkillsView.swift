import SwiftUI

struct SkillsView: View {
    @State private var query = ""
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private var filtered: [Skill] {
        query.isEmpty ? MockData.skills : MockData.skills.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(filtered) { SkillTile(skill: $0) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .background(AmbientGlow())
        .navigationTitle("Skills")
        .searchable(text: $query, prompt: "Search skills and tools")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { } label: { Image(systemName: "plus") }
            }
        }
    }
}

struct SkillTile: View {
    let skill: Skill
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                Text(skill.glyph).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(skill.color, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
                Circle().fill(skill.isEnabled ? Theme.online : .white.opacity(0.25))
                    .frame(width: 8, height: 8).padding(.top, 4)
            }
            Spacer()
            Text(skill.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
            Text("\(skill.toolCount) tools\(skill.isEnabled ? "" : " · Off")")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5)).padding(.top, 2)
        }
        .padding(14)
        .frame(height: 132)
        .glass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true)
        .opacity(skill.isEnabled ? 1 : 0.6)
    }
}

#Preview { NavigationStack { SkillsView() }.preferredColorScheme(.dark) }
