import SwiftUI

struct RootView: View {
    private let store: SessionStore

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSidebarItem: SidebarItem? = .sessions
    @State private var statusViewModel = StatusViewModel()
    @State private var isShowingStatusPopover: Bool = false

    init(store: SessionStore) {
        self.store = store
    }

    var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            Rectangle()
                .fill(LoomTheme.backgroundGradient(colorScheme))
                .opacity(colorScheme == .dark ? 0.08 : 0.06)
                .ignoresSafeArea()

            NavigationSplitView {
                sidebar
            } detail: {
                detailContent
            }
            .navigationSplitViewStyle(.prominentDetail)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    statusPillButton
                }
            }
        }
        .task {
            if selectedSidebarItem == nil {
                selectedSidebarItem = .sessions
            }
            statusViewModel.startMonitoring()
        }
        .onDisappear {
            statusViewModel.stopMonitoring()
        }
    }

    private var sidebar: some View {
        List(selection: $selectedSidebarItem) {
            Section("Work") {
                sidebarRow(.sessions)
            }

            Section("System") {
                sidebarRow(.models)
                sidebarRow(.status)
            }

            Section("App") {
                sidebarRow(.settings)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        .navigationTitle("Loom")
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSidebarItem ?? .sessions {
        case .sessions:
            SessionsWorkspaceView(
                store: store,
                browseModels: {
                    selectedSidebarItem = .models
                },
                openOrInstallOllama: {
                    statusViewModel.openOrInstallOllama()
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("root.detail.sessions")
        case .models:
            ModelsView(
                onModelSelectionChanged: {
                    await statusViewModel.refresh()
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("root.detail.models")
        case .status:
            StatusView(
                viewModel: statusViewModel,
                browseModels: {
                    selectedSidebarItem = .models
                }
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("root.detail.status")
        case .settings:
            SettingsView(store: store)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("root.detail.settings")
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        let isSelected = selectedSidebarItem == item

        return Label(item.title, systemImage: item.systemImage)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("sidebar.\(item.id)")
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LoomTheme.accentGradient(colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.10))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.14), lineWidth: 1)
                }
            }
            .tag(item)
    }

    private var statusPillButton: some View {
        Button {
            isShowingStatusPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: statusViewModel.snapshot.readiness.symbolName)
                    .font(.caption.bold())
                    .foregroundStyle(statusViewModel.snapshot.readiness.tintColor)
                Text("Loom")
                    .font(.subheadline.weight(.semibold))
                Text(statusViewModel.snapshot.readiness.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusViewModel.snapshot.readiness.tintColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingStatusPopover, arrowEdge: .bottom) {
            LoomStatusPopoverView(
                viewModel: statusViewModel,
                browseModels: {
                    selectedSidebarItem = .models
                    isShowingStatusPopover = false
                }
            )
        }
    }
}
