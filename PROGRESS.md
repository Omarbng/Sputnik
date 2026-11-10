# ClipDock — progress

## Status
- [x] **M0 — Skeleton** (awaiting Omar's check)
- [ ] M1 — Capture
- [ ] M2 — Popup + paste
- [ ] M3 — Translation
- [ ] M4 — Pins, paste all, settings
- [ ] M5 — UI pass
- [ ] M6 — Claude translation (optional)

## Decisions
- **2026-11-10 · Toolchain: SwiftPM + Command Line Tools instead of XcodeGen/xcodebuild.**
  Xcode isn't installed, and the disk was nearly full. The CLT ship Swift 6.2.3 and the
  macOS 26.2 SDK, which include Translation, NaturalLanguage, and Swift Testing.
  `Package.swift` replaces `project.yml`. `run.sh` runs `swift build`, assembles
  `build/ClipDock.app`, signs it, installs it to `~/Applications`, and relaunches it.
  Omar approved this.
- **Signing:** a self-signed "ClipDock Dev" code-signing certificate (10 years) in the
  login keychain. Its designated requirement is
  `identifier "com.omar.clipdock" and certificate leaf = H"231f26f7…"`, and it stays the
  same across rebuilds, so TCC permissions persist.
- **Deployment target:** macOS 26.0 (`sw_vers` = 26.0).
- **Translation (for M3):** in SDK 26.2, `TranslationSession(installedSource:target:)` is
  `@available(macOS 26.0)`, not 26.4 as the brief says. On this Mac a session can be created
  directly, so the hidden `.translationTask` view isn't needed. Confirm with Omar at M3.
- Dependencies get added in the milestone that needs them: GRDB in M1, KeyboardShortcuts in M2.

## Known issues
- Disk space is tight (about 2.6 GB free after deleting a stale Cursor update). Quitting
  Cursor installs its pending update and frees about 1.4 GB more.
