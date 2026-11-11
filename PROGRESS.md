# ClipDock — progress

## Status
- [x] **M0 — Skeleton** (Omar checked it on 2026-11-10)
- [x] **M1 — Capture** (Claude tested it end to end on 2026-11-10, as Omar asked)
- [x] **M2 — Popup + paste** (Claude tested it, see "M2 test results"; Omar still needs to press ⌘⇧V himself)
- [x] **M3 — Translation** (works end to end with the stand-in translator. The real Apple
  engine needs the English and Russian downloads, which Omar must confirm in the macOS prompt)
- [x] **M4 — Pins, paste all, settings** (Claude tested it, see "M4 test results")
- [x] **M5 — UI pass** (built to section 5 as written, as Omar chose on 2026-11-10. It
  needs Omar's sign-off on the look and motion)
- [x] **Shortcut change** (2026-11-11, Omar): Wispr-Flow-style double-taps replace the combos
  (see below)
- [x] **M5b — Clip actions and Saved items** (2026-11-11, Omar's request; see "M5b test
  results"). Needs Omar to try Touch ID, right-click, and the row buttons himself.
- [ ] M6 — Claude translation (optional; Omar hasn't decided yet)
- [ ] **M7 — Dictation (planned, Omar's request on 2026-11-11):** after ClipDock is finished,
  write up what an on-device voice-dictation feature would take, in quality, effort, and
  what it can and can't match in Wispr Flow, before building anything. It's outside the
  brief's original scope (section 9).

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
  - `Popup/`: panel, controller (split into core, `+Commands`, `+Editor`), AppKit shell, and
    SwiftUI list. `Popup/Actions/` is the actions menu; `Popup/Editor/` is the ⌘N/⌘E editor.
  - `Saved/`: saved items (`SavedItems`), secrets (`SecretStore` for the Keychain,
    `SecretActions` for paste/copy, `OwnerCheck` for Touch ID).
  - `Paste/`: writer, ⌘V sender, secure input, and Accessibility.
  - `HUD/`, `Onboarding/` (cards), `MenuBar/`, `Hotkeys/`, `Images/` (icon and thumbnail caches).
  - `Debug/`: debug-build-only hooks.
- `Sources/ClipDockCore` also holds `PopupPlacement`, `PopupKeymap`, `EditorKeymap`, `ClipAction`,
  `HistoryFilter` (with the History/Saved scopes), `TextCleanup`, and `Thumbnailer`.
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
- **Translation engine (M3):** in SDK 26.2, `TranslationSession(installedSource:target:)` is
  `@available(macOS 26.0)`, not 26.4 as the brief says.
  - `AppleTranslator` (an actor) creates sessions directly and keeps one warm per direction.
    A failed session is dropped so the next try starts fresh. There's no hidden
    `.translationTask` view for translating.
  - SwiftUI's `.translationTask` is used only by the one-time "Download English and Russian"
    card, because `prepareTranslation()` needs it to show the system download prompt.
  - Everything sits behind the `Translator` protocol, ready for the Claude engine in M6.
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
- **Language detection:** more than 30% Cyrillic letters (U+0400–U+052F) means Russian.
  Otherwise `NLLanguageRecognizer` gets the final say. Russian goes RU → EN; everything else
  goes EN → RU. Only the first 2,000 characters are examined.
- **Long text:** `TextLayout` splits text by line, keeping each line's leading and trailing
  whitespace, blank lines, and the exact line breaks (including `\r\n`). The lines go to
  the engine as one batch, then are put back together.
- **In place (⌥⌘T):**
  1. Suspend capture and snapshot the whole pasteboard.
  2. Send ⌘C and wait up to 300 ms for `changeCount` to change.
  3. Detect the language and translate. If that takes more than 150 ms, show "Translating…".
  4. Write the translation (marked internal) and send ⌘V.
  5. After 500 ms, restore the snapshot and resume capture.
  6. Record the translation in history with `isTranslation`.
  - The temporary ⌘C copy is never stored.
  - The translation shortcuts fire on key-up.
  - Without Accessibility, or with secure input on, it stops with a HUD.
- **Show only (⇧⌥⌘T):** steps 1–3, restoring the clipboard right away, then a card at the
  cursor with Copy (⌘C) and Esc. Copy also records the translation in history.
- **Popup ⌘T:** the translation (or its progress, or an error) appears under the row. ↩ and
  ⌘C act on the translation while it's shown.
- **Database migration v2** adds `isTranslation`, shown as a "translated" badge.
- **Debug:** `CLIPDOCK_FAKE_TRANSLATOR=1` swaps in a stand-in translator that tags each line
  (`[ru] …`), so the flow can be tested without the language files.
- **Pins (⌘P):** pinned items sit in a Pinned section, never expire, don't count toward the
  item limit, and survive Clear history.
- **Multi-select:** Space marks the selected row, and marked rows show their order number.
  ⌘↩ joins the marked items' text in that order with the separator (newline, space,
  ", ", or nothing) and pastes once. Images are left out, with a HUD. Without marks, ⌘↩
  acts like ↩. **Space always marks, as in the brief's key table**, so search queries
  can't contain spaces and are effectively single-term.
- **Settings window (⌘, or Settings…):**
  - Shortcut recorders, history limit (50–5,000), and retention days (1–365). New limits
    apply when the window closes, so stepping past a value by mistake doesn't delete anything.
  - Paste-all separator, and ignored apps (add with a file picker, remove, restore defaults).
  - Launch at login (`SMAppService.mainApp`).
  - Permission and download status, with buttons.
  - The Claude engine, key, and model fields arrive in M6.
- **Menu:**
  - Open ClipDock, then Pause Capture (15 min, 1 hour, until resumed) or Resume Capture
    with "Paused until …".
  - Clear History… (confirms first, and keeps pinned items), Settings…, Quit.
  - Setup items appear only while something still needs a permission or download.
- **Pause** is stored in `pausedUntil`, so it survives a relaunch. Copies made during a pause
  are never read. The icon shows an empty clipboard while paused.
- **Focus:** closing a ClipDock window calls `NSApp.deactivate()`, and `Paster` won't send
  ⌘V while ClipDock itself is frontmost. It shows "Copied — press ⌘V" instead.
- **Shortcuts: double-taps (Omar, 2026-11-11).**
  - Tap ⌥ twice to open the clipboard. Tap ⌃ twice to translate the selected text.
  - Translating shows a card at the cursor: ↩ Replace pastes over the still-selected text and
    restores the clipboard, ⌘C copies, and Esc closes. That one flow replaces ⌥⌘T and ⇧⌥⌘T.
  - `ModifierTapDetector` (Core, 8 tests) counts a tap only for a lone modifier press and
    release under 0.35 s, with the second press within 0.4 s. Combos, key presses, and clicks
    cancel it, and block taps until every modifier is released. It fires on the second release.
  - `DoubleTapMonitor` uses global and local `NSEvent` monitors, which need Accessibility. It
    restarts when Accessibility is granted.
  - Settings has a picker per action (⌥, ⌃, ⌘, ⇧, or Off). Picking the other action's key
    swaps the two. Optional KeyboardShortcuts combos have no default.
  - The stored old combos (⌘⇧V and friends) are removed once at launch, which also gives ⌘⇧V
    back to Chrome.
  - The brief's section 3 is updated to match.
- **Space** marks items only while the search box is empty. With text in the box it types a
  space, so multi-word search works. Omar chose this on 2026-11-10, over the brief's "Space
  always marks".
- **M5 design (section 5):**
  - `Design/Tokens` holds the shadcn neutral colours, dark plus inverted light, following the
    system appearance.
  - `Design/Motion` holds the springs: slide 0.7/650/44, reveal 0.7/720/52, collapse
    0.9/460/42. The fade is 180 ms with `timingCurve(0.22, 1, 0.36, 1)`. With Reduce Motion,
    movement is instant and fades take 120 ms.
  - `Design/MaterialBackground` is a behind-window blur (masked `NSVisualEffectView`) under a
    95% fill, with a 1 pt border and a large shadow. The dock, card, HUD, and translation card
    all share it.
- **Popup layout:**
  - The dock pill is 48 pt, with 32 pt buttons and 2 pt gaps: History, Pinned, Translate,
    Paste all, Settings, then a divider and the toggle.
  - Under it is a 360 pt card with 18 pt corners, holding the search field and the list.
  - The panel is larger than what you see (tooltip room plus shadow margins). Placement
    positions the visible stack at the cursor.
- **Dock behaviour:**
  - History and Pinned switch the list's scope, and the active one is filled.
  - The Pinned badge shows when anything is pinned. The Paste-all badge shows while items
    are marked.
  - The toggle collapses the pill toward itself (it never moves), and the card fades out.
    Any key or typing expands it again. Each open starts expanded.
- **Tooltip rail:** one inverted surface holding every label side by side. It slides (`x`)
  and clips (`width`) to the hovered button. The first hover appears in place. Hover is
  tracked with `onContinuousHover` across the whole dock, so moving between buttons doesn't
  flicker.
- **Selected row:** a capsule with `matchedGeometryEffect`, animated with the slide spring.
- **HUD and show-only card:** same material, fading in and out over 180 ms.
- **Debug hooks:** `dock`, `hover`, and `snapshot` render the popup to a PNG with
  `cacheDisplay`, since screenshots need Screen Recording.
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

## M3 test results (2026-11-10, stand-in translator, CDTarget test app)
- In place, English, multi-paragraph: replaced with the layout kept, byte for byte, including
  the blank line, indentation, and trailing newline. The clipboard came back identical (every
  item and type compared), and undo restored the original.
- In place, Russian: RU → EN, with the clipboard identical afterwards.
- Nothing selected: "Select some text first" (`nothingCopied`), with nothing changed.
- Show only: the card appeared, nothing was replaced, and the clipboard was identical.
- Popup ⌘T: the translation appeared under the row, and ↩ pasted it into the target app.
- History: every translation was stored with `isTranslation=1`. The temporary ⌘C copies were
  not stored.
- Still to do once the languages are downloaded: the same run with Apple's engine
  (`MODE=real`), and the brief's TextEdit and Safari checks.

## M4 test results (2026-11-10, scripted)
- ⌘P pinned the top item.
- Space on alpha → beta → gamma then ⌘↩ pasted `alpha\nbeta\ngamma` into the test app.
  With the comma separator it pasted `beta, alpha, gamma`, in the marked order.
- Pause until resumed: a copy during the pause wasn't saved, and one after Resume was.
  A 2-second pause resumed by itself.
- Clear history left only the pinned item. The DB-level unit test also checks that its blob
  survives while the others are deleted.
- ⌘, in the popup opened Settings, and closing it left the previous app in front.
- Settings persisted across a relaunch: limits 400 and 20 days, separator, a sixth ignored
  app, and a custom shortcut.
- Unit tests: 65, including pinned items surviving the 30-day retention with a faked clock.
- Omar's history and settings were backed up before the run and restored afterwards.

## M5 test results (2026-11-11)
- Snapshots of the expanded dock, tooltip, mid-slide, and collapsed states match section 5.1
  and 5.4.
- Open time with the new UI: 17–42 ms over 6 opens. The target is under 100 ms.
- Regression on the new UI: the M3 scenarios (in place, show only, popup ⌘T), paste all, and
  the Space rule all pass.

## Double-tap test results (2026-11-11)
- Real HID modifier events posted by a debug hook: ⌥⌥ was detected and opened the popup,
  and ⌃⌃ on selected text opened the card without touching the text.
- Replace put the translation in place, and Copy copied it. The clipboard was identical
  afterwards in both cases.
- Popup lifetime check: double-tap and toggle opens behaved the same. One early close
  (`resignedKey`) lined up with another app taking focus while Omar was using the Mac.

## M5b test results (2026-11-11, test build, in-app hooks, CDTarget test app)
- 96 unit tests pass (23 new: saved-item storage, the actions list, clean-up, editor keys,
  the History/Saved scopes, and secrets in search and Paste all).
- ⌘N with a name and text saved a pinned, named item and switched to Saved. ⌘N, ⌘L, name,
  value, then ↩ (or ⌘S) saved a secret: the row's text is NULL, the value is in the Keychain,
  and it's in none of ClipDock's files, its preferences, or its logs.
- Pasting a secret put its value in the test app; the clipboard afterwards was byte-for-byte
  what it was before. Copying one marked it `ConcealedType`, history didn't capture it, and
  31 s later the clipboard was back to what it was before the copy.
- ⌘K opened the menu with the expected actions; ↑↓ moved; Esc closed only the menu.
- ⌥↩ on an RTF item pasted text only (no RTF on the pasteboard). "Paste without Extra Spaces"
  pasted joined paragraphs and added them to history. ⌘E then ⌘↩ pasted the edit and kept the
  original; ⌘E then ⌘S replaced the text and dropped the RTF blob.
- ⌘⌫ deleted a plain item at once; a saved item showed "Delete?" and went on the second ⌘⌫;
  deleting a secret removed its Keychain item. Space on a secret didn't mark it.
- Snapshots: the Saved tab (lock and dots for secrets, ⋯ and trash on hover), the menu, and
  the "Delete?" pill look as designed. The menu was 13 pt too tall for ten actions; rows are
  now 24 pt.
- Omar's history, clipboard, and Keychain were left as they were: test rows and the test
  Keychain items were removed, and the everyday build was reinstalled.

## M5b decisions (2026-11-11)
- **Omar chose** (AskUserQuestion): all four extra actions (plain text, open/show, edit, clean
  up); a Saved tab with Keychain secrets; saved items in every search; and "picking acts,
  nothing opens", so the editor lives inside the popup.
- **History without a search shows only unsaved items.** Saved items join any search, under
  "Saved". Otherwise a long Saved list would push the latest copy off ↩ and ⌘1.
- **Saved = pinned.** Typed-in items and secrets are stored pinned, so retention and Clear
  history already keep them. New columns `name` and `secretRef` (migration `v3-saved-items`),
  and a new `ClipKind.secret`, so every `switch` over kinds has to handle secrets.
- **Secrets:** the value is a generic-password item in the login Keychain (service
  `com.omar.clipdock.saved`, account = a UUID in `secretRef`). The row's `text` is NULL and its
  content hash is `secret:<UUID>`, so no hash of the value is stored either.
  - Touch ID is an app-level check (`LAContext`, `.deviceOwnerAuthentication`), asked on every
    paste and copy. The data-protection Keychain (which could enforce it) needs a provisioning
    profile, which a self-signed app can't have.
  - Pasting restores the old clipboard after 500 ms; copying clears it after 30 s unless
    something else was copied. Both writes carry `org.nspasteboard.ConcealedType`.
- **⌥↩** works on any text; Paste as Plain Text appears in the menu only for text that has
  formatting. Files get "Paste as Path".
- **Clean-up and edited pastes** are added to history (what's now in the document), with the
  target app as the source.
- **Deleting a saved item asks first** (second ⌘⌫ or click), because typed-in items and
  secrets can't be copied again.
- **⇥ switches History/Saved**, so the Saved tab works without the mouse.
- **Test builds** (`CLIPDOCK_TEST_BUILD=1 ./run.sh`) compile in a Touch ID skip and a
  "⌘V only into the test target" guard, both off unless launched with their environment
  variables. The everyday build has neither.

## Known issues
- **After a rebuild, the first use of each secret shows a Keychain password prompt**
  ("ClipDock wants to use your confidential information…"). The self-signed certificate has
  no Team ID, so the Keychain ties the item to the exact build. Choose **Always Allow**. It
  doesn't happen between rebuilds.
- Not tested by Claude (needs a person at the Mac): the real Touch ID prompt and whether focus
  returns to the app afterwards (if it doesn't, the secret stays copied for 30 s), a real
  right-click, clicking the row's ⋯ and trash buttons, and ⌘O (it opens a browser tab or a
  Finder window).
- Not tested by Claude: the motion itself (springs and fades, which snapshots can't show), and
  how the blur looks over real windows.
- Not tested by Claude: the look of the Settings window, and turning on Launch at login
  (it changes the login items, so that's left for Omar).
- Not tested by Claude:
  - The physical ⌘⇧V press. The script opens the popup through the same `toggle()` call.
  - Notes, so as not to edit Omar's notes.
  - Slack, which isn't installed.
  - What the HUD and popup look like, because screenshots need Screen Recording permission.
- `NSApp.isActive` reads true while the popup is open, but the frontmost app doesn't change
  (logged before and after each open). Pastes land in the right app.
- Text is translated line by line, so a sentence hard-wrapped across lines is translated in
  pieces.
- Images are pasted as PNG only. Very old apps that read only TIFF won't accept them.
- The 1Password (`com.1password.1password`, `com.agilebits.onepassword7`) and Bitwarden
  (`com.bitwarden.desktop`) bundle IDs aren't verified, because neither app is installed.
  Both also mark copies with `ConcealedType`, which is skipped anyway.
- Disk space is tight (about 1.5 GB free). Quitting Cursor installs its pending update and
  frees about 1.4 GB.
