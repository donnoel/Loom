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
| ✍️ **Readable Chat Formatting** | Assistant text is auto-formatted into human-readable paragraphs and list-friendly markdown when raw output arrives as a dense block. |
| ⏹️ **Stop Generation** | Cancel generation any time and keep the partial assistant response. |
| 🧠 **Helpful Setup Gating** | Clear in-context guidance if no active model is selected or Ollama is unavailable. |
| 🧩 **Model Picker** | View installed Ollama models, choose an active model, and keep that selection across launches until you change it. |
| 🩺 **Readiness Status** | Dedicated Status view + toolbar pill showing ready/setup/not-ready state. |
| 📤 **Markdown Export** | Export any session to Markdown (`⌘⇧E` command + toolbar action). |
| 🔒 **Privacy-First by Default** | Chats and model usage stay local to your Mac. |

---

## 🎛 Controls (simple by design)

- **Create Session** with the `+` toolbar button
- **Rename/Delete** from toolbar or session context menu
- **Type + Send** in the message field to start a local model response
- **Stop** to cancel streaming while keeping partial text
- **Export Session** from toolbar or `⌘⇧E`
- **Status / Models** from sidebar for setup and diagnostics
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
- Exposes inline banner state for guidance

### **Root UI (SwiftUI + NavigationSplitView)**
- Sidebar areas: Sessions, Models, Status, Settings
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
├── UI/
│   ├── Root/
│   ├── Sessions/
│   ├── Models/
│   ├── Status/
│   ├── Settings/
│   └── Sidebar/
├── Utilities/
│   └── FileSystem/
│       └── LoomPaths.swift
└── Resources/
    └── Assets.xcassets/
```

Also included:
- `LoomTests/`
- `LoomUITests/`

---

## 🧪 Tests

`LoomTests` currently includes coverage for streaming parser behavior in `OllamaChatClient`:
- Delta chunk parsing
- Done chunk parsing
- Error chunk parsing
- Whitespace/empty line handling

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
