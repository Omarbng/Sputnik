# ClipDock — progress

## Status
- [x] **M0 — Skeleton** (Omar checked it on 2026-11-10)
- [x] **M1 — Capture** (awaiting Omar's check)
- [ ] M2 — Popup + paste
- [ ] M3 — Translation
- [ ] M4 — Pins, paste all, settings
- [ ] M5 — UI pass
- [ ] M6 — Claude translation (optional)

## How to build and test
- `./run.sh` builds, signs, installs to `~/Applications/ClipDock.app`, and relaunches.
- `./test.sh` runs the unit tests (Swift Testing).
- Logs: `/usr/bin/log show --last 5m --style compact --predicate 'subsystem == "com.omar.clipdock"'`.
  Use the full path, because zsh has a built-in `log` command that shadows it.

## Layout
- `Sources/ClipDockCore`: pure logic and storage, with no AppKit. Holds the models,
  `SkipRules`, `RetentionPolicy`, and `HistoryDatabase` (GRDB) plus `BlobStore`.
- `Sources/ClipDock`: the app. `Capture/` (watcher, reader, pipeline, access),
  `History/HistoryModel` (in-memory list), `Onboarding/` (paste-permission card), `MenuBar/`.
- `Tests/ClipDockCoreTests`: dedupe, skip rules, and retention.

## Decisions
- **2026-11-10 · Toolchain: SwiftPM + Command Line Tools instead of XcodeGen/xcodebuild.**
  Xcode isn't installed, and the disk was nearly full. The CLT ship Swift 6.2.3 and the
  macOS 26.2 SDK. Omar approved this.
- **Signing:** a self-signed "ClipDock Dev" code-signing certificate (10 years) in the
  login keychain. Its designated requirement is
  `identifier "com.omar.clipdock" and certificate leaf = H"231f26f7…"`, and it stays the
  same across rebuilds, so TCC permissions persist.
- **Build output lives in `~/Library/Caches/ClipDock-build/`.** The project is on the
  iCloud-synced Desktop, and iCloud tagged an in-project `.app` mid-codesign. `run.sh`
  also makes the staged bundle writable and strips xattrs before signing.
- **Swift Testing without Xcode:** `swiftpm-env.sh` adds the CLT framework folder
  (`-F`) for both scripts, so they share one build cache. `Package.swift` turns off
  cross-import overlays for the test target only, because the CLT lack the
  `_Testing_Foundation` module file.
- **Deployment target:** macOS 26.0 (`sw_vers` = 26.0).
- **Translation (for M3):** in SDK 26.2, `TranslationSession(installedSource:target:)` is
  `@available(macOS 26.0)`, not 26.4 as the brief says. A session can be created directly,
  without the hidden `.translationTask` view. Confirm with Omar at M3.
- **Capture:**
  - Priority is files, then text or URL, then image. A lone http(s) URL is a `url`. A web
    URL that comes with an image (a browser's "Copy Image") is stored as the image.
  - Dedupe key is SHA-256 of kind plus content (text, URL, paths, or PNG bytes). A
    duplicate moves to the top and takes the newer source app.
  - RTF and PNG go in `blobs/<sha256>.<ext>`, so the in-memory list stays small. TIFF-only
    images are converted to PNG off the main thread, in `CapturePipeline`.
  - The 10 MB limit applies to what would be stored, after PNG conversion.
  - Whatever is on the pasteboard at launch is not captured. That way relaunching doesn't
    reorder history.
  - Retention runs at launch and after every capture.
- **Paste permission:** on this Mac, `NSPasteboard.general.accessBehavior` already reports
  `.alwaysAllow` on macOS 26.0, so the card hasn't shown yet. Its flow:
  - In `.default`, the Continue button does one deliberate read. That makes macOS prompt
    and list ClipDock in Settings.
  - In `.ask` or `.alwaysDeny`, there's an "Open System Settings" button
    (`…security?Privacy_Pasteboard`).
  - The card closes itself once the permission becomes `.alwaysAllow`.
  - It appears on its own once. After that, the menu shows "Capture Off — Allow Clipboard
    Access…" while capture is off.
  - The menu-bar icon is `clipboard` while capture is off and `doc.on.clipboard` while on.
- **Logging:** `notice` level, so messages are kept and visible in `log show`. They contain
  only ids, kinds, sizes, and skip reasons.
- Dependencies get added in the milestone that needs them: GRDB 7.12 in M1,
  KeyboardShortcuts in M2.

## Known issues
- The temporary "Recent" section in the menu (M1 only) is replaced by the popup in M2.
- The 1Password (`com.1password.1password`, `com.agilebits.onepassword7`) and Bitwarden
  (`com.bitwarden.desktop`) bundle IDs aren't verified, because neither app is installed.
  Both also mark copies with `ConcealedType`, which is skipped anyway.
- Disk space is tight (about 1.5 GB free). Quitting Cursor installs its pending update and
  frees about 1.4 GB.
