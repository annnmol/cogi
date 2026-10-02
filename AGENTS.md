# Project instructions

- Read `prd.md` and relevant existing code before editing. Implement only the requested task using the smallest complete, production-ready change. Preserve unrelated code, user edits, public behavior, and platform interoperability; avoid speculative refactors, dependencies, and abstractions.
- Use `android-dev` (`.codex/agents/android-dev.toml`) for Android/Kotlin/Compose tasks and `mac-dev` (`.codex/agents/mac-dev.toml`) for macOS/Swift/SwiftUI tasks. Delegate to the appropriate specialist when required. If custom roles are unavailable, give a worker the corresponding file's instructions. Use relevant skills only when needed; these restrictions take precedence over skill workflows.
- For tasks spanning both platforms, assign distinct files to each agent. Coordinate shared protocol changes through one owner and update both consumers consistently.
- V1: plain text, LAN only, up to five trusted devices, native APIs, authenticated encrypted connections, persistent trust, local history, and event deduplication. No backend, cloud, accounts, custom cryptography, or Android clipboard restriction bypasses. Follow `protocol/PROTOCOL.md` when present.
- Change code promptly after targeted file reads. Do not create or run tests, builds, app launches, debuggers, profiling, linters, or automated validation commands. The user handles all execution and verification manually.
- Do not run any Git commands or perform Git operations, including commit, push, pull, fetch, checkout, reset, stash, or staging.
- Finish with a concise list of changes and any concrete limitations. State that execution and verification were left to the user; never claim the app was verified.
