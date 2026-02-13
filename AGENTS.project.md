# AGENTS.project.md

# Loom (macOS) Project Guide for Agents

## Product intent
**Loom** is a macOS-first, offline-first local LLM workspace designed for non-technical users.
Core values: **privacy, resilience, calm UX, Apple-native polish**.

## Current product phase (updated)
We have the V1 local chat spine in place:
1) **Sessions** are disk-backed (list/create/delete/rename/export)
2) **messages.jsonl** is append-only per session
3) **Local Ollama model selection + status** are integrated
4) **Streaming assistant responses** are integrated end-to-end
5) **Stop/cancel generation** keeps partial output and persists it

Current focus should be reliability, polish, and guardrails (not sweeping architecture rewrites).

## Architecture snapshot (current)
- **SwiftUI** with `NavigationSplitView` for macOS layout.
- **MVVM**: view models on the MainActor; services/IO actors off-main.
- **SessionStore** (`actor`) owns persistence and session recency updates.
- **OllamaClient** (`actor`) handles diagnosis, reachability, and model listing via local HTTP.
- **OllamaChatClient** (`actor`) streams chat via `POST /api/chat` and parses line-delimited JSON chunks.
- **SessionMessagesViewModel** orchestrates send flow, in-memory streaming updates, banners, cancellation, and persistence.

## Disk layout (Application Support)
- `~/Library/Application Support/Loom/Sessions/<UUID>/metadata.json`
- `~/Library/Application Support/Loom/Sessions/<UUID>/messages.jsonl` (append-only)

## Concurrency rules (important)
We are using Swift 6 concurrency checks. Do NOT silence them by adding broad `@MainActor`.
- `Session`, `Session.Metadata`, `ChatMessage`, and filesystem helpers (e.g. `LoomPaths`) must remain **nonisolated** (no `@MainActor`).
- UI state and SwiftUI view models can be `@MainActor`.
- Persistence/network actor methods may be `async` and called from MainActor view models.
- Streaming callbacks must never block the main thread.

## Chat behavior invariants (do not regress)
When user sends a message:
1) Persist user message first.
2) Append a local assistant placeholder immediately.
3) Stream deltas into only that placeholder message in memory.
4) On completion, persist assistant message.
5) On cancel, keep and persist partial assistant text.
6) On mid-stream failure, keep partial text and show gentle guidance.

Additional expectations:
- Keep the user draft intact if send fails.
- Throttle/coalesce streaming UI updates (currently ~50ms).
- Keep context bounded (currently last 20 messages).
- If active model changes for a session (including after leaving and returning), use user-only context for the next turn to avoid old-model anchoring.
- Avoid full message-list reload per token.

## Setup-gating UX rules
Use plain language and actionable buttons.
- No active model: **"Choose a model to chat with."**
- Ollama unreachable: **"Loom can’t reach Ollama. Start it to continue."**
- Avoid jargon (ports, localhost, API details) in user-facing copy.

## User experience goals
- Calm, simple, “Finder-like” interactions.
- Sessions feel like documents/projects.
- Rename should feel native (context menu rename; inline edit; Return commits; Escape cancels).
- Chat should feel immediate: quick placeholder + live stream + stable scrolling.

## Coding conventions
- Prefer append-only JSONL for messages: each line is one JSON object (`ChatMessage`).
- Writes: `.atomic` for metadata; append for messages via `FileHandle`.
- Log with `OSLog` instead of `print`.
- Reuse `OllamaClient` base-URL resolution; do not duplicate fragile host logic.

## When editing persistence
- Preserve backward compatibility if you change the on-disk format.
- Keep operations robust: missing files should not crash; treat as empty.
- Favor deterministic sorting (e.g., `updatedAt` descending for sessions).

## Build/run notes
- Target: macOS app (SwiftUI).
- Maintain **clean build**: no warnings.
- App Intents metadata generation is disabled in build settings to keep builds warning-clean for this target set.
- If you introduce new files, ensure they are included in the correct target.

## Near-term priorities
- Strengthen automated tests for send/stream/cancel/failure persistence paths.
- Improve message rendering polish (rich text/markdown-safe display).
- Harden retry/recovery UX for transient local runtime failures.
- Continue model management and trust-center roadmap items without compromising local-first behavior.

## Output expectations per patch
Provide:
- Summary of change
- Files modified
- Any migration considerations
- Commit message suggestion
