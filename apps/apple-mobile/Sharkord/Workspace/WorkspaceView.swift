import SwiftUI

/// picks the native layout for the device: a tab bar plus a push stack on iPhone, a split view on iPad.
/// keeping the switch in one place is what lets both layouts share a single channel detail screen.
struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var channelPath: [String] = []

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadWorkspace
            } else {
                iPhoneWorkspace
            }
        }
        .background(BrandBackground())
    }

    private var iPhoneWorkspace: some View {
        TabView {
            NavigationStack(path: $channelPath) {
                ChannelListView(model: model, selectedID: model.selectedChannelID, onSelect: selectForPush)
                    .navigationDestination(for: String.self) { id in
                        ChannelDetailView(model: model, channelID: id)
                    }
            }
            .tabItem { Label("频道", systemImage: "number") }

            MembersView(model: model)
                .tabItem { Label("成员", systemImage: "person.2") }

            SettingsView(model: model)
                .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
        }
        .tint(.sharkordBlue)
        .onChange(of: channelPath) { _, path in
            if path.isEmpty {
                model.selectedChannelID = nil
            }
        }
    }

    private var iPadWorkspace: some View {
        NavigationSplitView {
            ChannelListView(model: model, selectedID: model.selectedChannelID, onSelect: selectInPlace)
                .navigationTitle(model.serverDisplayName)
        } detail: {
            if let id = model.selectedChannelID {
                ChannelDetailView(model: model, channelID: id)
            } else {
                emptyDetail
            }
        }
    }

    private func selectForPush(_ id: String) {
        model.selectedChannelID = id
        channelPath.append(id)
    }

    private func selectInPlace(_ id: String) {
        model.selectedChannelID = id
    }

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("选择一个频道")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandBackground())
    }
}
