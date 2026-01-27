# AGENTS.project.md

# Loom (macOS) Project Guide for Agents

## Product intent
**Loom** is a macOS-first, offline-first local LLM workspace designed for non-technical users.
Core values: **privacy, resilience, calm UX, Apple-native polish**.

## Current build phase (V1 spine)
We are building in this order:
1) **Sessions** (disk-backed, list/create/delete/rename)
2) **messages.jsonl** (append-only chat log per session)
3) Basic chat UI rendering + input (still local-only)
4) Loom Engine integration (Ollama/local runtime)
5) Model library + updates + trust center

Do not jump ahead to model runtime until the session + message storage foundation is solid.

## Architectural decisions
- **SwiftUI** with `NavigationSplitView` for macOS layout.
- **MVVM**: view models on the MainActor; services/IO actors off-main.
- **SessionStore** is an `actor` and owns persistence.
- Disk layout (Application Support):
  - `~/Library/Application Support/Loom/Sessions/<UUID>/metadata.json`
  - `~/Library/Application Support/Loom/Sessions/<UUID>/messages.jsonl` (append-only)

## Concurrency rules (important)
We are using Swift 6 concurrency checks. Do NOT silence them by adding broad `@MainActor`.
- `Session`, `Session.Metadata`, `ChatMessage`, and filesystem helpers (e.g. `LoomPaths`) must remain **nonisolated** (no `@MainActor`).
- UI state and SwiftUI view models can be `@MainActor`.
- Persistence actor methods may be `async` and called from MainActor view models.

## File layout (expected)
- `App/` app entry
- `UI/` SwiftUI views
- `Core/` pure models/domain
- `Services/` actors/services (persistence, engine, connectivity)
- `Utilities/` helpers (filesystem paths, logging)

## User experience goals
- Calm, simple, “Finder-like” interactions.
- Sessions feel like documents/projects.
- Rename should feel native (context menu rename; inline edit; Return commits; Escape cancels).
- No scary terminology in UI (avoid “quantization”, “VRAM”, etc. unless in an advanced view).

## Coding conventions
- Prefer append-only JSONL for messages: each line is one JSON object (`ChatMessage`).
- Writes: `.atomic` for metadata; append for messages via `FileHandle`.
- Log with `OSLog` instead of `print`.

## When editing persistence
- Preserve backward compatibility if you change the on-disk format.
- Keep operations robust: missing files should not crash; treat as empty.
- Favor deterministic sorting (e.g., updatedAt descending for sessions).

## What to implement next (nearest tasks)
- Ensure messages file is created on session creation.
- Add `appendMessage` and `loadMessages` to SessionStore.
- Render messages in the detail view (simple list/bubbles).
- Add input field to append user messages (no LLM yet).
- Add export (Markdown) later.

## Build/run notes
- Target: macOS app (SwiftUI).
- Maintain **clean build**: no warnings.
- If you introduce new files, ensure they’re included in the correct target.

## Output expectations per patch
- Provide:
  - Summary of change
  - Files modified
  - Any migration considerations
  - Commit message suggestion
