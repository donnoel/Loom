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
| 🗂️ **Session Workspace** | Create, rename, delete, search, pin, archive, and sort sessions by recent activity. |
| 🏷️ **Auto Session Titles** | New sessions are renamed from your first prompt so conversations are easier to scan later. |
| 💾 **Disk-Backed Persistence** | Each chat stores `metadata.json`, append-only `messages.jsonl`, and an optional `scratchpad.txt`; shared preferences live in a global `memory.json`. |
| ⚡ **Streaming Assistant Replies** | Assistant responses stream live into the UI as tokens arrive. |
| 🎙️ **Speech Input (Push-to-Talk)** | Use the mic button to dictate directly into the draft field with on-device speech recognition. |
| 🔊 **Optional Voice Replies** | Toggle read-aloud mode so new assistant replies are spoken after generation completes, using your chosen voice from Settings. |
| 📎 **File Upload Grounding** | Attach local text/PDF files and Loom injects extracted excerpts as context for the next turn, with size/count guardrails and automatic context-budget trimming. Files are not copied into chat storage. |
| 🎚️ **Composer Context Controls** | Choose concise/balanced/extended history and off/compact/full file context from the composer, with quieter UI defaults. |
| 🧭 **Capability-Aware Guidance** | Model cards and chat composer clearly show which models support speech input/output and file uploads. |
| 💬 **Animated Typing Pulse** | While Loom is generating, assistant placeholders show a pulsing typing indicator. |
| ✍️ **Readable Chat Formatting** | Assistant text is normalized for paragraph/list readability when raw output arrives as a dense block, while keeping stable whitespace-preserving rendering during streaming to avoid visual "snap back." |
| 🎨 **Chat-First Workspace Styling** | The app uses a cleaner dark workspace with flatter surfaces, calmer sidebar emphasis, and a simplified composer to keep focus on conversation content. |
| 💡 **Starter Prompt Chips** | New sessions include one-tap prompt suggestions that prefill the composer to help non-technical users get started quickly. |
| 🧰 **Chat Templates** | Use four customizable prompt templates from the composer and edit or reset them in Settings. |
| 📌 **Session Organization** | Pin important chats, archive old ones without deleting them, and use sidebar search across chat titles and messages. |
| 📝 **Per-Session Scratchpad** | Keep lightweight notes beside a chat without adding them to the transcript. |
| 🧾 **Global Memory** | Save a few user-edited reply preferences and optionally include them in future turns across every chat. |
| 🔀 **Model Compare Mode** | Run one prompt against two installed local models side by side without changing the active chat. |
| 🪄 **Assistant Quick Actions** | Copy replies as plain text/Markdown or create follow-up turns that summarize, simplify, professionalize, or checklist a response. |
| ⏹️ **Stop Generation** | Cancel generation any time and keep the partial assistant response. |
| 🧠 **Helpful Setup Gating** | Clear in-context guidance if no active model is selected or Ollama is unavailable. |
| 🔁 **Model-Aware Context Switching** | If the active model changes for a session, the next turn uses user-only context to avoid old-model anchoring. |
| 🔀 **In-Session Model Switcher** | Change the active model directly from the chat composer without leaving the current session. |
| 🧩 **Model Picker** | View installed Ollama models with plain-language "good for" guidance plus maker/country and last-trained details, use streamlined actions (Set Active / Update / Delete), and keep model selection across launches until you change it. |
| ↕️ **Drag-Reorder Models** | Reorder installed models in Model Library with drag-and-drop, and Loom remembers your order across refresh/relaunch. |
| 📥 **In-App Model Install** | Use **Add Model…** to browse a focused curated catalog (Qwen 3.5 9B, DeepSeek R1 8B, Gemma 3 4B, Gemma 4 E4B), review friendly summaries, and install with live progress + cancel support. |
| 🧹 **Model Cleanup** | Delete installed models directly from Loom (with confirmation and active-model safety checks). |
| 💽 **Disk Awareness** | Model Library shows local free-space info and warns when free space is below 10%. |
| 🩺 **Readiness Status** | Model Library + toolbar pill show ready/setup/not-ready state in plain language. |
| 📤 **Markdown Export** | Export any session to Markdown (`⌘⇧E` command + toolbar action). |
| 🔒 **Privacy-First by Default** | Chats and model usage stay local to your Mac. |

---

## 🎛 Controls

- **Create a New Chat** with the square-and-pencil toolbar button or the always-visible sidebar entry
- **Auto-Name New Sessions** by sending your first message (title is derived from the opening request)
- **Browse Chats** directly in the sidebar
- **Search Chats** from the sidebar to find matching chat titles or message snippets
- **Rename/Pin/Archive/Delete** from toolbar or session context menu
- **Type + Send** in the message field to start a local model response
- **Tap Starter Prompts** in a new session to prefill a question instantly
- **Attach Files** with the paperclip button to add local text/PDF context
  Limits: up to 8 files, max ~2 MB per text file, max ~5 MB per PDF, and excerpt trimming when total attachment context is too large.
  Extracted context is used for that turn and is not saved as a persistent chat attachment.
- **Dictate Message** with the mic button (when supported by the active model)
- **Read Replies Aloud** with the speaker toggle (when supported by the active model)
- **Switch Models In Session** from the combined model/tools menu above the composer
- **Tune Context Before Send** from the same `Tools` menu (history + file inclusion)
- **Compare Models** from the sidebar to send one prompt to two installed models side by side
- **Use Global Memory** from the chat toolbar to edit local reply preferences shared across chats
- **Use Chat Templates** from the composer menu; edit or reset the four templates in Settings
- **Open Scratchpad** from the session toolbar to keep notes beside the transcript
- **Use Assistant Quick Actions** from an assistant message context menu to copy or transform a reply
- **Tune Voice Quality** in Settings with a voice picker and preview button
- **Auto-Correct + Spell Check** in the message field (uses your macOS Keyboard settings)
- **Stop** to cancel streaming while keeping partial text
- **Jump to Bottom** with the floating down-arrow when you scroll up in long chats
- **Export Session** from toolbar or `⌘⇧E`
- **Models** from sidebar for setup, diagnostics, and update checks in one place
- **Reorder Installed Models** by dragging model cards in Model Library
- **Add Model…** from Model Library to install curated models without leaving Loom
- **Automation toggles** in Settings let you disable background status/model checks and use manual Refresh instead

---

## 🧠 Architecture Overview

### **SessionStore (actor)**
Persistence owner for sessions and messages:
- Bootstraps app storage folders
- CRUD for session metadata
- Append-only JSONL writes for chat messages
- Atomic scratchpad and global memory writes, including migration from legacy per-session memory
- Deterministic session sorting via `updatedAt`

### **SessionSearchService (actor)**
Search coordinator for saved sessions:
- Searches session titles and message contents
- Returns snippets that can jump back into the matching chat
- Keeps per-session read failures isolated so one bad transcript does not break search

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
- Loads and saves per-session scratchpad notes
- Applies optional global memory preferences to request context
- Loads installed-model choices for in-session switching and keeps active-model preference in sync
- Exposes model capability gating for speech/file tools and inline guidance
- Exposes inline banner state for guidance

### **CompareModeViewModel (@MainActor)**
Side-by-side local model comparison coordinator:
- Loads installed Ollama models for left/right selection
- Runs the same prompt against two different models
- Keeps compare output separate from normal chat transcripts

### **Root UI (SwiftUI + NavigationSplitView)**
- Sidebar areas: Sessions, Models, Compare, Settings
- Status pill in toolbar with quick readiness visibility (shows `Checking…` until initial local status refresh completes)
- Session detail optimized for steady, low-jank streaming updates

---

## 🗄️ Data Layout

Loom stores data in Application Support:

```text
~/Library/Application Support/Loom/
├── memory.json
└── Sessions/
    └── <UUID>/
        ├── metadata.json
        ├── messages.jsonl
        └── scratchpad.txt
```

Notes:
- `metadata.json` writes are atomic
- `messages.jsonl` is append-only (one JSON message per line)
- `scratchpad.txt` is local to one chat and writes atomically when saved
- The root `memory.json` stores optional global reply preferences and writes atomically
- If global memory is missing, Loom can migrate a legacy per-session `memory.json` when that chat is opened

---

## 📁 Project Structure

```text
Loom/
├── App/
│   └── LoomApp.swift
├── Core/
│   ├── Sessions/
│   │   ├── Session.swift
│   │   ├── ChatMessage.swift
│   │   ├── SessionMemory.swift
│   │   └── SessionSearchResult.swift
│   ├── Templates/
│   │   └── ChatTemplateLibrary.swift
│   └── VoiceReplyVoiceCatalog.swift
├── Services/
│   ├── SessionStore.swift
│   ├── SessionSearchService.swift
│   └── Ollama/
│       ├── OllamaClient.swift
│       └── OllamaChatClient.swift
├── Models/
│   └── ModelCatalog.swift
├── UI/
│   ├── Compare/
│   ├── Root/
│   ├── Sessions/
│   ├── Models/
│   ├── Status/
│   ├── Settings/
│   ├── Sidebar/
│   └── Theme/
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
- `SessionStore` scratchpad persistence plus global memory sharing and legacy migration
- `ChatTemplateLibrary` template persistence and reset behavior
- `SessionSearchService` title and message search
- `ChatDisplayFormatter` dense-text paragraph/list normalization behavior
- `ModelCatalog` loading and curated model lookups
- `DiskSpaceSnapshot` probe-path ordering/deduplication rules
- `SessionMessagesViewModel` send/stream/cancel/retry/failure/model-switch context flows
- `SessionMessagesViewModel` context controls (history/file modes), context budgeting, and attachment-context toggles
- `ModelsViewModel` refresh/install/update/delete and safety rails
- `RootViewModel` load/rename/pin/archive/tags/delete flows
- `StatusViewModel` local Ollama/model readiness behavior
- `CompareModeViewModel` two-model compare behavior and validation
- `OllamaChatClient` stream-line parsing and transport-level stream error mapping
- `OllamaClient` diagnosis/list/delete/pull network-path behavior via mocked transport

`LoomUITests` covers key end-to-end desktop flows:
- Models recovery navigation from setup guidance
- Session create/delete
- Setup guidance when no model is active
- Streaming reply path
- Return-key sending and compact composer layout
- Long model-label layout safety for composer send-button hittability
- Stop generation with relaunch verification

---

## 🚀 Getting Started

1. Install **Ollama** on your Mac (`https://ollama.com/download`)  
2. Start Ollama (app launch or `ollama serve`)  
3. Pull at least one model from Loom's current catalog (example: `ollama pull qwen3.5:9b`)
4. Open `Loom.xcodeproj` in a current Xcode with the macOS 26.2 SDK available
5. Build and run the **Loom** scheme  
6. In Loom, open **Models** and select an active model  
7. Open or create a chat and start chatting

To reproduce the warning-clean CI build and test locally:

```sh
xcodebuild \
  -project Loom.xcodeproj \
  -scheme Loom \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" \
  GCC_TREAT_WARNINGS_AS_ERRORS=YES \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
  clean test
```

---

## 🗺️ Roadmap

- [ ] Refine session search/filtering polish
- [ ] Improve message rendering polish (bubbles + richer markdown)
- [ ] Add chat export enhancements
- [ ] Deepen model update workflows
- [ ] Continue hardening local engine resiliency and diagnostics

---

## Credits

Built with care by **Don Noel** and Codex collaboration.

---

> *Loom is designed to make local AI feel calm, capable, and private by default.*
