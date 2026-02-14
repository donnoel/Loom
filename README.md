# 🧵 **Loom**
### *An offline-first local LLM workspace for macOS.*

<p align="center">
  <img src="https://img.shields.io/badge/SwiftUI-MVVM-orange?logo=swift">
  <img src="https://img.shields.io/badge/Platform-macOS-blue">
  <img src="https://img.shields.io/badge/Runtime-Ollama_(local)-green">
  <img src="https://img.shields.io/badge/Storage-JSONL-purple">
</p>

---

## ✨ What is Loom?

**Loom** is a macOS-first workspace for local AI chats.

It is built for people who want a clean, Finder-like experience with **local-first privacy**:
- Sessions that behave like lightweight project documents
- Chat history stored on disk per session
- Local model inference through **Ollama**
- Helpful setup guidance when anything is missing

---

## 💎 Core Features

| Feature | Description |
|--------|-------------|
| 🗂️ **Session Workspace** | Create, rename, delete, and sort sessions by recent activity. |
| 💾 **Disk-Backed Persistence** | Each session stores `metadata.json` + append-only `messages.jsonl`. |
| ⚡ **Streaming Assistant Replies** | Assistant responses stream live into the UI as tokens arrive. |
| 🎙️ **Speech Input (Push-to-Talk)** | Use the mic button to dictate directly into the draft field with on-device speech recognition. |
| 🔊 **Optional Voice Replies** | Toggle read-aloud mode so new assistant replies are spoken after generation completes. |
| 📎 **File Upload Grounding** | Attach local text/PDF files and Loom injects extracted excerpts as context for the next turn, with size/count guardrails and automatic context-budget trimming. |
| 🧭 **Capability-Aware Guidance** | Model cards and chat composer clearly show which models support speech input/output and file uploads. |
| 💬 **Animated Typing Pulse** | While Loom is generating, assistant placeholders show a pulsing typing indicator. |
| ✍️ **Readable Chat Formatting** | Assistant text is normalized for paragraph/list readability when raw output arrives as a dense block, while keeping stable whitespace-preserving rendering during streaming to avoid visual "snap back." |
| 🎨 **Bold Workspace Styling** | Chat bubbles use richer layered gradients and depth, and sidebar selection uses a stronger highlighted chrome for quick scanning. |
| ⏹️ **Stop Generation** | Cancel generation any time and keep the partial assistant response. |
| 🧠 **Helpful Setup Gating** | Clear in-context guidance if no active model is selected or Ollama is unavailable. |
| 🔁 **Model-Aware Context Switching** | If the active model changes for a session, the next turn uses user-only context to avoid old-model anchoring. |
| 🧩 **Model Picker** | View installed Ollama models with plain-language "good for" guidance plus maker/country and last-trained details, use streamlined actions (Set Active / Update / Delete), and keep model selection across launches until you change it. |
| ℹ️ **System Info Sheet** | Open **App → Info** in the sidebar to see a plain-language walkthrough of how Loom, Ollama, and local models work together, with official source links per company. |
| 📥 **In-App Model Install** | Use **Add Model…** to browse a curated catalog, review friendly model summaries, and install with live progress + cancel support. |
| 🧹 **Model Cleanup** | Delete installed models directly from Loom (with confirmation and active-model safety checks). |
| 💽 **Disk Awareness** | Model Library shows local free-space info and warns when free space is below 10%. |
| 🩺 **Readiness Status** | Model Library + toolbar pill show ready/setup/not-ready state in plain language. |
| 📤 **Markdown Export** | Export any session to Markdown (`⌘⇧E` command + toolbar action). |
| 🔒 **Privacy-First by Default** | Chats and model usage stay local to your Mac. |

---

## 🎛 Controls

- **Create Session** with the `+` toolbar button
- **Browse Sessions** directly in the sidebar (chat-list style)
- **Rename/Delete** from toolbar or session context menu
- **Type + Send** in the message field to start a local model response
- **Attach Files** with the paperclip button to add local text/PDF context
  Limits: up to 8 files, max ~2 MB per text file, max ~5 MB per PDF, and excerpt trimming when total attachment context is too large.
- **Dictate Message** with the mic button (when supported by the active model)
- **Read Replies Aloud** with the speaker toggle (when supported by the active model)
- **Auto-Correct + Spell Check** in the message field (uses your macOS Keyboard settings)
- **Stop** to cancel streaming while keeping partial text
- **Jump to Bottom** with the floating down-arrow when you scroll up in long chats
- **Export Session** from toolbar or `⌘⇧E`
- **Models** from sidebar for setup, diagnostics, and update checks in one place
- **Add Model…** from Model Library to install curated models without leaving Loom
- **Automation toggles** in Settings let you disable background status/model checks and use manual Refresh instead

---

## 🧠 Architecture Overview

### **SessionStore (actor)**
Persistence owner for sessions and messages:
- Bootstraps app storage folders
- CRUD for session metadata
- Append-only JSONL writes for chat messages
- Deterministic session sorting via `updatedAt`

### **OllamaClient (actor)**
Connectivity + model discovery:
- Probes resilient local endpoints (`localhost`, `127.0.0.1`, `[::1]`)
- Caches the last reachable base URL
- Provides plain-language diagnosis for setup UX
- Lists installed models from Ollama API
- Pulls and deletes models via Ollama HTTP endpoints with install-progress streaming

### **OllamaChatClient (actor)**
Streaming chat transport:
- Uses `POST /api/chat` with streaming enabled
- Parses line-delimited JSON stream chunks
- Emits incremental assistant deltas
- Surfaces user-friendly error states

### **SessionMessagesViewModel (@MainActor)**
Chat interaction coordinator:
- Loads/persists messages per session
- Applies model + reachability gating before send
- Inserts assistant placeholder and updates content while streaming
- Supports cancellation and partial persistence
- Supports retry/regenerate and model-switch-safe context behavior
- Adds local attachment excerpts into request context for file-aware turns
- Enforces attachment guardrails (file count, file size, and total context budget) with plain-language skip guidance
- Exposes model capability gating for speech/file tools and inline guidance
- Exposes inline banner state for guidance

### **Root UI (SwiftUI + NavigationSplitView)**
- Sidebar areas: Sessions, Models, Settings
- Status pill in toolbar with quick readiness visibility
- Session detail optimized for steady, low-jank streaming updates

---

## 🗄️ Data Layout

Loom stores data in Application Support:

```text
~/Library/Application Support/Loom/
└── Sessions/
    └── <UUID>/
        ├── metadata.json
        └── messages.jsonl
```

Notes:
- `metadata.json` writes are atomic
- `messages.jsonl` is append-only (one JSON message per line)

---

## 📁 Project Structure

```text
Loom/
├── App/
│   └── LoomApp.swift
├── Core/
│   └── Sessions/
│       ├── Session.swift
│       └── ChatMessage.swift
├── Services/
│   ├── SessionStore.swift
│   └── Ollama/
│       ├── OllamaClient.swift
│       └── OllamaChatClient.swift
├── Models/
│   └── ModelCatalog.swift
├── UI/
│   ├── Root/
│   ├── Sessions/
│   ├── Models/
│   ├── Status/
│   ├── Settings/
│   └── Sidebar/
├── Utilities/
│   └── FileSystem/
│       ├── LoomPaths.swift
│       └── DiskSpace.swift
└── Resources/
    ├── Assets.xcassets/
    └── ModelCatalog.json
```

Also included:
- `LoomTests/`
- `LoomUITests/`

---

## 🧪 Tests

`LoomTests` includes focused coverage across persistence, formatting, services, and view models:
- `SessionStore` create/update/delete + append/load JSONL behavior
- `ChatDisplayFormatter` dense-text paragraph/list normalization behavior
- `ModelCatalog` loading and curated model lookups
- `DiskSpaceSnapshot` probe-path ordering/deduplication rules
- `SessionMessagesViewModel` send/stream/cancel/retry/failure/model-switch context flows
- `ModelsViewModel` refresh/install/update/delete and safety rails
- `RootViewModel` load/rename/pin/tags/delete flows
- `OllamaChatClient` stream-line parsing and transport-level stream error mapping
- `OllamaClient` diagnosis/list/delete/pull network-path behavior via mocked transport

`LoomUITests` covers key end-to-end desktop flows:
- Sidebar navigation
- Session create/delete
- Setup guidance when no model is active
- Streaming reply path
- Stop generation with relaunch verification

---

## 🚀 Getting Started

1. Install **Ollama** on your Mac (`https://ollama.com/download`)  
2. Start Ollama (app launch or `ollama serve`)  
3. Pull at least one model (example: `ollama pull llama3.2`)  
4. Open `Loom.xcodeproj` in Xcode  
5. Build and run the **Loom** scheme  
6. In Loom, open **Models** and select an active model  
7. Open/create a session and start chatting

---

## 🗺️ Roadmap

- [ ] Expand session search/filtering tools
- [ ] Improve message rendering polish (bubbles + richer markdown)
- [ ] Add chat export enhancements
- [ ] Deepen trust center + model update workflows
- [ ] Continue hardening local engine resiliency and diagnostics

---

## ❤️ Credits

Built with care by **Don Noel** and AI collaboration.

---

> *Loom is designed to make local AI feel calm, capable, and private by default.*
