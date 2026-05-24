import SwiftUI

struct CompareModeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var vm = CompareModeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                modelSelectionRow
                promptComposer
                actionRow
                resultsRow
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Compare")
        .task {
            await vm.loadModels()
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Compare Two Models")
                .font(LoomTheme.Typography.pageHero)
            Text("Send one prompt and review both responses side by side.")
                .font(LoomTheme.Typography.body)
                .foregroundStyle(.secondary)
            if let bannerText = vm.bannerText {
                Text(bannerText)
                    .font(LoomTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 12)
    }

    private var modelSelectionRow: some View {
        HStack(spacing: 10) {
            pickerCard(title: "Left Model", selection: $vm.leftModelTag)
            pickerCard(title: "Right Model", selection: $vm.rightModelTag)
        }
    }

    private func pickerCard(title: String, selection: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(LoomTheme.Typography.captionStrong)
                .foregroundStyle(.secondary)

            Picker(title, selection: selection) {
                ForEach(vm.availableModelTags, id: \.self) { tag in
                    Text(tag).tag(Optional(tag))
                }
            }
            .labelsHidden()
            .disabled(vm.availableModelTags.isEmpty || vm.isRunningCompare)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .loomCard(cornerRadius: 10)
    }

    private var promptComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(LoomTheme.Typography.captionStrong)
                .foregroundStyle(.secondary)

            TextEditor(text: $vm.prompt)
                .font(LoomTheme.Typography.body)
                .frame(minHeight: 110, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .disabled(vm.isRunningCompare)
                .accessibilityIdentifier("compare.prompt")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button("Compare") {
                Task { await vm.runCompare() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isRunningCompare || vm.availableModelTags.count < 2)

            if vm.isRunningCompare {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()
        }
    }

    private var resultsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            resultCard(title: vm.leftModelTag ?? "Left")
            resultCard(title: vm.rightModelTag ?? "Right", isLeft: false)
        }
    }

    private func resultCard(title: String, isLeft: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(LoomTheme.Typography.bodyStrong)
                .lineLimit(1)

            Group {
                switch isLeft ? vm.leftState : vm.rightState {
                case .idle:
                    Text("Run compare to see this response.")
                        .foregroundStyle(.secondary)
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating response…")
                            .foregroundStyle(.secondary)
                    }
                case .success(let text):
                    Text(text)
                        .textSelection(.enabled)
                case .failure(let message):
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
            .font(LoomTheme.Typography.body)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .loomCard(cornerRadius: 12)
    }
}
