import SwiftUI

struct SessionMemorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var memory: SessionMemory

    let onSave: (SessionMemory) async -> Void

    init(memory: SessionMemory, onSave: @escaping (SessionMemory) async -> Void) {
        _memory = State(initialValue: memory)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Memory")
                .font(.title3.weight(.semibold))

            Text("Remember a few preferences for this session only. Everything stays on this Mac and can be edited or cleared here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Use memory in replies", isOn: $memory.isEnabled)
                .accessibilityHint("Controls whether these saved preferences are included in replies for this session.")

            memoryTextField(
                title: "Call me",
                placeholder: "For example, Don",
                text: $memory.preferredUserName,
                limit: SessionMemory.userNameLimit
            )
            memoryTextField(
                title: "Call yourself",
                placeholder: "For example, Loom",
                text: $memory.preferredAssistantName,
                limit: SessionMemory.assistantNameLimit
            )
            memoryTextField(
                title: "Response style",
                placeholder: "For example, Keep answers short and conversational",
                text: $memory.responseStyle,
                limit: SessionMemory.responseStyleLimit
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Short session note")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Button("Clear") {
                        memory.sessionNote = ""
                    }
                    .disabled(memory.sessionNote.isEmpty)
                }

                TextEditor(text: $memory.sessionNote)
                    .font(.body)
                    .frame(height: 68)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                    .accessibilityLabel("Short session note")
                    .onChange(of: memory.sessionNote) { _, value in
                        memory.sessionNote = String(value.prefix(SessionMemory.sessionNoteLimit))
                    }
            }

            HStack {
                Button("Clear All") {
                    let usesMemory = memory.isEnabled
                    memory = SessionMemory(isEnabled: usesMemory)
                }
                .disabled(memory == SessionMemory(isEnabled: memory.isEnabled))

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    Task {
                        await onSave(memory)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func memoryTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        limit: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Clear") {
                    text.wrappedValue = ""
                }
                .disabled(text.wrappedValue.isEmpty)
            }
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _, value in
                    text.wrappedValue = String(value.prefix(limit))
                }
        }
    }
}
