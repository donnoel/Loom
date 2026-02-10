# AGENTS.md

This repo is an Apple-platform app codebase. You are an engineering agent (Codex) collaborating with the human. Your job is to make small, correct, testable changes with a clean build at every step.

## Hard requirements (do not violate)
- **No build warnings.** Treat warnings as errors in practice.
- **No large rewrites.** Prefer small, surgical diffs.
- **Apple-native only.** No third-party libraries unless explicitly requested.
- **SwiftUI + MVVM.** Keep UI declarative; isolate logic in view models/services.
- **Concurrency correctness.** Avoid `@MainActor` on data models / filesystem / networking types. Use actors/services for isolation.
- **File persistence must be safe.** Use atomic writes where appropriate; prefer append-only logs for chat.
- **Privacy-first.** Local-only by default. No unexpected network calls.
- **Preserve chat behavior contracts.** Do not regress streaming, stop/cancel, or setup-gating UX without explicitly calling it out.

## Workflow
1. Read existing code and architecture before editing.
2. Propose a minimal plan in 2–5 bullets.
3. Implement the smallest viable patch.
4. Ensure build passes with **zero warnings**.
5. If tests exist or are touched, run them. Add tests for non-trivial logic.
6. If behavior changed, update docs (`README.md` / `AGENTS.project.md`) in the same patch.

## Code style
- Keep types small and focused.
- Prefer `Foundation` + `OSLog` over ad-hoc prints.
- Use `actor` for mutable shared state (e.g., disk stores/network services).
- Prefer `@MainActor` only for UI/view models that must touch SwiftUI state.
- Avoid global singletons (unless explicitly designed).
- For streaming UI updates, coalesce deltas to avoid SwiftUI hitching.

## Deliverables for each change
- Mention which files were modified and why.
- Provide a short commit message suggestion.
- Mention any user-visible behavior changes explicitly.

## What not to do
- Don’t introduce new dependencies.
- Don’t “fix” code by disabling concurrency checks.
- Don’t add `@MainActor` broadly to silence warnings.
- Don’t change public behavior without stating it.
- Don’t shell out to Ollama CLI from app logic; use local HTTP services.
- Don’t replace plain-language setup guidance with technical jargon.

If something is ambiguous, default to the simplest solution that preserves correctness and forward progress.
