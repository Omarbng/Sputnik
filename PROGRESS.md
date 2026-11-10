# ClipDock — progress

## Status
- [x] **M0 — Skeleton** (Omar checked it on 2026-11-10)
- [x] **M1 — Capture** (Claude tested it end to end on 2026-11-10, as Omar asked)
- [x] **M2 — Popup + paste** (Claude tested it, see "M2 test results"; Omar still needs to press ⌘⇧V himself)
- [ ] M3 — Translation
- [ ] M4 — Pins, paste all, settings
- [ ] M5 — UI pass
- [ ] M6 — Claude translation (optional)

## How to build and test
- `./run.sh` builds, signs, installs to `~/Applications/ClipDock.app`, and relaunches.
- `./test.sh` runs the unit tests (Swift Testing).
- Live tests: see `Tools/README.md`. A debug build launched with
  `open --env CLIPDOCK_DEBUG_HOOKS=1 ~/Applications/ClipDock.app` accepts scripted commands.
- Logs: `/usr/bin/log show --last 5m --style compact --predicate 'subsystem == "com.omar.clipdock"'`.
  Use the full path, because zsh has a built-in `log` command that shadows it.

## Layout
- `Sources/ClipDockCore`: pure logic and storage, with no AppKit. Holds the models,
  `SkipRules`, `RetentionPolicy`, and `HistoryDatabase` (GRDB) plus `BlobStore`.
- `Sources/ClipDock`: the app.
  - `Capture/`: watcher, reader, pipeline, and access.
  - `History/`: the in-memory model and item actions.
  - `Popup/`: panel, controller, AppKit shell, and SwiftUI list.
  - `Paste/`: writer, ⌘V sender, secure input, and Accessibility.
  - `HUD/`, `Onboarding/` (cards), `MenuBar/`, `Hotkeys/`, `Images/` (icon and thumbnail caches).
  - `Debug/`: debug-build-only hooks.
- `Sources/ClipDockCore` also holds `PopupPlacement`, `PopupKeymap`, `HistoryFilter`, and `Thumbnailer`.
- `Tests/ClipDockCoreTests`: dedupe, skip rules, retention, placement, search, keymap, and touch/delete.
- `Vendor/KeyboardShortcuts`: a patched copy of the library (see below).
- `Tools/`: test helpers.

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
- **KeyboardShortcuts 2.4.0 is vendored** in `Vendor/KeyboardShortcuts` (MIT, with the
  upstream commit recorded). It has two patches, both described in its `Package.swift`:
  1. Its `#Preview` blocks are removed, because the Previews macro plugin ships only with Xcode.
  2. Localized strings load from `Contents/Resources`, because SwiftPM's `Bundle.module` looks
     in the `.app` root, where codesign doesn't allow a bundle.
- **Secure input:** `IsSecureEventInputEnabled` has no header in SDK 26.2, so it's looked up
  with `dlsym`. It's verified to work: the fallback HUD appeared with secure input on.
- **Popup:**
  - The shell is AppKit: an `NSVisualEffectView` and an `NSTextField`, so focus is reliable
    on every open. The list is SwiftUI.
  - It's a fixed 360×341 pt (8 rows of 36 pt), with plain styling until M5.
  - It's warmed once at launch with an invisible render. That brought the first open from
    190 ms down to 30 ms.
  - Keys go through a local key monitor and `PopupKeymap`, by key code, so they're
    layout-independent.
  - ⌘C and ⌘⌫ also work in M2. ⌘A, ⌘X, and ⌘V edit the search text, because a menu-bar app
    has no Edit menu.
  - Search is case-insensitive and needs every word to match, over the text (first 2,000
    characters) and the source app name.
- **Paste:**
  1. Write to the pasteboard with the internal marker.
  2. Close the popup.
  3. Wait `Paster.delay` (50 ms).
  4. Send ⌘V (`kVK_ANSI_V`).
  - With no Accessibility, it shows "Copied — press ⌘V". With secure input on, it shows
    "Can't paste here — copied instead".
  - Pasting or copying from history moves the item to the top.
- **Onboarding:** an Accessibility card appears once at launch if access isn't granted.
  After that, the menu shows "Allow Pasting…".
- **Debug hooks** load only when launched with `CLIPDOCK_DEBUG_HOOKS=1`. Otherwise any local
  process could drive pastes, or read whether a field contains some text, through
  ClipDock's permissions.

## M2 test results (2026-11-10, driven by script)
- Popup at 4 corners plus the centre of the 1470×956 screen: fully on screen every time
  (pushed below the menu bar, kept left of the right edge, above the cursor near the bottom).
- Open time: 30 ms on the first open after the warm-up, then 17–26 ms.
- ↩ pasted into TextEdit, and ⌘1 pasted into a Chrome textarea. Both were confirmed by
  reading the field back through Accessibility.
- With the Russian keyboard layout active, ↩ pasted into TextEdit correctly.
- With secure input on, ClipDock didn't paste and showed the "Can't paste here" HUD.
- ↑↓ selection, search (case-insensitive), "No matches", Esc, and ⌘⌫ delete all work.
  Losing focus closes the popup.
- ClipDock's own writes are skipped by capture (`ownWrite`).
- The Accessibility permission survived several rebuilds, which confirms the stable signing.

## Known issues
- Not tested by Claude:
  - The physical ⌘⇧V press. The script opens the popup through the same `toggle()` call.
  - Notes, so as not to edit Omar's notes.
  - Slack, which isn't installed.
  - What the HUD and popup look like, because screenshots need Screen Recording permission.
- `NSApp.isActive` reads true while the popup is open, but the frontmost app doesn't change
  (logged before and after each open). Pastes land in the right app.
- Images are pasted as PNG only. Very old apps that read only TIFF won't accept them.
- The 1Password (`com.1password.1password`, `com.agilebits.onepassword7`) and Bitwarden
  (`com.bitwarden.desktop`) bundle IDs aren't verified, because neither app is installed.
  Both also mark copies with `ConcealedType`, which is skipped anyway.
- Disk space is tight (about 1.5 GB free). Quitting Cursor installs its pending update and
  frees about 1.4 GB.
