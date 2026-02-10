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
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            Rectangle()
                .fill(LoomTheme.backgroundGradient(for: colorScheme))
                .opacity(colorScheme == .dark ? 0.22 : 0.18)
                .ignoresSafeArea()

            NavigationSplitView {
                sidebar
            } detail: {
                detailContent
            }
            .navigationSplitViewStyle(.balanced)
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
        case .models:
            ModelsView(
                onModelSelectionChanged: {
                    await statusViewModel.refresh()
                }
            )
        case .status:
            StatusView(
                viewModel: statusViewModel,
                browseModels: {
                    selectedSidebarItem = .models
                }
            )
        case .settings:
            SettingsView()
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.systemImage)
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
                Text("Loom Ready")
                    .font(.subheadline.weight(.semibold))
                Text(statusViewModel.snapshot.readiness.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusViewModel.snapshot.readiness.tintColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(statusViewModel.snapshot.readiness.tintColor.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(statusViewModel.snapshot.readiness.tintColor.opacity(0.4), lineWidth: 1)
            )
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
