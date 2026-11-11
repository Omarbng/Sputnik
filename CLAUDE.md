# ClipDock — build brief

A tiny macOS menu-bar app for one person (Omar) on one Apple Silicon Mac. It has a single popup that opens at the mouse cursor. The popup holds clipboard history and offers English ⇄ Russian translation as an action. It's a personal tool, so it isn't for the App Store or for sharing.

**What matters most**

- **Instant:** the popup is visible less than 100 ms after the shortcut.
- **Keyboard-first:** everything works without the mouse.
- **Private:** nothing leaves the Mac, except the optional Claude translation mode.
- **Minimal:** no feature, setting, or screen we don't need.

---

## 1. How to work (rules for Claude Code)

- Build the milestones in section 6 in order. Don't start the next one until the current one's "Done when" checks pass and Omar has tried it.
- After each milestone, build and launch the app. Then give Omar 3–5 exact steps to test, and wait for his answer.
- Keep a short `PROGRESS.md` with what's done, the decisions made, and known issues.
- Several APIs here are new (macOS 15.4 to 26.4). **Check every Apple API name against the installed SDK before using it.** Don't guess signatures.
- Keep files small, with one responsibility each.
- Use `git init` at the start, and commit after each milestone.
- Ask Omar before you add a dependency that isn't listed below, change a default shortcut, or touch any data outside the app's own folder.

---

## 2. Tech decisions (already made)

| Area | Decision |
|---|---|
| Language / UI | Swift 6. Use SwiftUI for views and AppKit for the panel, menu bar, and keyboard events. **Native only, with no web views.** |
| Minimum macOS | Run `sw_vers` first and set the deployment target to this Mac's version, at least 15.0. |
| Project | ~~XcodeGen + xcodebuild~~ **Changed 2026-11-10 (Omar approved):** SwiftPM with the Command Line Tools, because Xcode isn't installed. `Package.swift` and `./run.sh` (`swift build` → assemble .app → sign → `~/Applications`). See PROGRESS.md. |
| App type | `LSUIElement = YES`, so the app lives in the menu bar with no Dock icon. **App Sandbox OFF**, because sending keystrokes and copying another app's selection don't work inside the sandbox. |
| Signing | Use a **stable identity** (see gotcha 8.1). In use: the self-signed "ClipDock Dev" certificate in the login keychain. |
| Global shortcuts | [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (SPM). Omar can change shortcuts in Settings. |
| Storage | [GRDB.swift](https://github.com/groue/GRDB.swift) (SQLite) in `~/Library/Application Support/ClipDock/`. Images and files go in a `blobs/` subfolder, named by content hash. |
| Launch at login | `SMAppService.mainApp` |
| Translation | Apple's **Translation** framework, which runs on the device. Claude API mode is optional and comes in M6. |
| Language detection | If more than 30% of the letters are Cyrillic, the text is Russian. Fall back to `NLLanguageRecognizer`. |
| Bundle id | `com.omar.clipdock`. Omar can change this. |

---

## 3. Default shortcuts

**Changed 2026-11-11 (Omar):** the combos were too complicated. The defaults are now
Wispr-Flow-style double-taps. All of these can be changed in Settings, and optional key
combos (such as ⌘⇧V) can still be recorded there.

| Action | Shortcut | Note |
|---|---|---|
| Open popup at cursor | tap ⌥ twice | |
| Translate selected text | tap ⌃ twice | A card shows the translation: ↩ replaces the selection, ⌘C copies, Esc closes. This replaces the old ⌥⌘T and ⇧⌥⌘T. |
| Translate with the other engine | (M6, to be decided) | Uses Claude if the default is Apple, or Apple if the default is Claude. |

**Inside the popup**

| Keys | Action |
|---|---|
| typing | Filter the list |
| ↑ ↓ | Move the selection |
| ⇥ | Switch between History and Saved (added 2026-11-11) |
| ↩ | Paste the selected item |
| ⌥↩ | Paste as plain text, or a file's path (added 2026-11-11) |
| ⌘1 – ⌘9 | Paste the Nth visible item |
| Space | Add or remove the item from multi-select (shows order numbers 1, 2, 3…) |
| ⌘↩ | Paste all selected items, in the order they were selected |
| ⌘K, or right-click a row | Actions menu for the item (section 4.9) (added 2026-11-11) |
| ⌘P | Add to Saved, or remove from it |
| ⌘T | Translate the selected item and show the result under it. ↩ pastes the translation. |
| ⌘E | Edit the item: ⌘↩ pastes the edited text, ⌘S saves it, Esc cancels (added 2026-11-11) |
| ⌘O | Open a link, or show a file in Finder (added 2026-11-11) |
| ⌘N | Type in a new saved item; ⌘L in the editor makes it a secret (added 2026-11-11) |
| ⌘C | Copy without pasting |
| ⌘⌫ | Delete the item. A saved item asks first: press ⌘⌫ again. |
| ⌘, | Open Settings |
| Esc | Close (or close the actions menu or editor) |

---

## 4. Features (behavior spec)

### 4.1 Clipboard capture
- macOS has no "clipboard changed" event. Poll `NSPasteboard.general.changeCount` every 0.3 s, and read the contents only when the count changes.
- **Capture these types:**
  - plain text (keep RTF alongside when it's present, so pasting keeps the formatting)
  - URLs
  - images, stored as PNG
  - file URLs, stored as paths
- **Source app:** at capture time, record `NSWorkspace.shared.frontmostApplication`'s bundle id and name.
- **Skip these:**
  - items carrying `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType`, or `org.nspasteboard.AutoGeneratedType`, which password managers use
  - items from ignored apps. The default list is 1Password, Bitwarden, Keychain Access, and Passwords, and Omar can edit it.
  - items larger than 10 MB (log the size only)
- **Our own writes:** whenever ClipDock writes to the pasteboard, add the private type `com.omar.clipdock.internal`, and ignore changes that carry it.
- **Dedupe:** if the content hash matches an existing item, move that item to the top instead of adding a copy. Pasting an item from history also moves it to the top.
- **Retention:** keep at most 500 unpinned items, and nothing older than 30 days. Pinned items never expire.
- **Pasteboard privacy (macOS 15.4+):**
  - There is a per-app "Paste from Other Apps" permission in System Settings → Privacy & Security, and `NSPasteboard` has an `accessBehavior` property. Check the SDK for the exact cases.
  - Check `accessBehavior` on launch. If it isn't "always allow", show a one-time card. The card explains why ClipDock needs **Allow** and has a button that opens that Settings pane.
  - If access is "ask", **stop polling** until it's allowed, so Omar doesn't get an alert on every copy.

### 4.2 Popup at the cursor
- **The window:**
  - It's an `NSPanel` subclass: borderless, `.nonactivatingPanel`, floating level, and `canBecomeKey = true`.
  - Set `collectionBehavior` to `[.canJoinAllSpaces, .fullScreenAuxiliary]` so it also opens over full-screen apps.
  - It is non-activating so the app Omar is typing in stays frontmost, and the paste goes back into it.
- **Position:**
  - Open at the cursor, offset by (+8, −8).
  - Clamp it to the `visibleFrame` of the screen that contains the cursor, so it works with multiple monitors.
  - If there isn't room below the cursor, open above it.
- **Speed:**
  - Create the panel once at launch and only show or hide it after that.
  - Keep the history in memory.
  - Measure the open time with `os_signpost` and print it in debug builds. The target is under 100 ms.
- **Close** on Esc, a click outside, choosing an item, or focus loss.
- **Search:** the search field is focused when the popup opens. Filtering is instant and case-insensitive, and matches the text and the source app name.
- **Sections:** ~~Pinned on top, then Recent.~~ **Changed 2026-11-11 (Omar chose "saved items
  in every search"):** History shows recent copies only, so ↩ and ⌘1 always reach the latest
  copy. While searching, matching saved items come first, under "Saved". The Saved tab lists
  only saved items.
- **Each row shows:**
  - a type glyph
  - the first line of text, an image thumbnail, or the file name
  - the source app's icon
  - the relative time ("2m")
- **How pasting works:**
  1. Write the item to the pasteboard, marked internal.
  2. Close the panel.
  3. Wait about 50 ms.
  4. Send ⌘V with `CGEvent`. Use virtual key code `kVK_ANSI_V` (9), **not the character**, so it still works when the Russian keyboard layout is active.
  5. If Accessibility isn't granted, only copy the item, and show a HUD that says "Copied — press ⌘V".

### 4.3 Paste all
- Space adds an item to the multi-select, and each selected row shows its order number.
- ⌘↩ joins the selected items in that order and pastes them once.
- The separator is a setting: newline (the default), space, comma, or nothing.

### 4.4 Translate

**In place (⌥⌘T), with text selected in any app:**
1. Save the full current pasteboard contents, with all items and types.
2. Send ⌘C. Wait for `changeCount` to change, with a 300 ms timeout. If nothing changes, show the HUD "Select some text first" and stop.
3. Detect the language. Russian text becomes English, and everything else becomes Russian.
4. Translate it. If that takes more than 150 ms, show a small "Translating…" HUD at the cursor.
5. Write the translation to the pasteboard, marked internal, and send ⌘V. This replaces the selection.
6. After about 500 ms, restore the original pasteboard contents.
7. Add the translation to history with a "translated" badge. Don't store the temporary ⌘C copy.
8. Omar can undo with ⌘Z in the target app as usual.

**Show only (⇧⌥⌘T):** run steps 1–3, then show the translation in a small card at the cursor. The card has a Copy button and Esc closes it. Use this for text that can't be edited, such as web pages and PDFs.

**From the popup (⌘T):** the translation appears under the selected row. ↩ pastes the translation and ⌘C copies it.

**Apple engine:**
- **First run:** check `LanguageAvailability.status(from:to:)` for en→ru and ru→en. If either pair isn't installed, call `prepareTranslation()` during onboarding so the system download prompt appears once.
- **Getting a session:**
  - On macOS 26.4+, create one directly with `TranslationSession(installedSource:target:)`, which needs no UI.
  - On older versions, the only way to get a session is SwiftUI's `.translationTask`. Host a tiny invisible SwiftUI view that lives as long as the app, owns the `.translationTask`, and serves requests through an async queue.
  - Hide both paths behind one `Translator` protocol, and choose between them at runtime.
- Keep one warm session for each direction.
- **Long text:** split it by paragraph, translate the parts as a batch, and rejoin them. Keep the line breaks and the leading and trailing whitespace.

**Claude engine (M6, optional):**
- **Settings:** a choice of default engine, an API key, and a model id.
  - Store the key in the **Keychain** only, never in files or logs.
  - Default the model id to the current recommended model listed at docs.claude.com. Check it when building.
- **Prompt:**

  > Translate to {target}. Business register; use formal "Вы" in Russian. Keep names, numbers, product names and formatting. Output only the translation.

- **Fallback:** after an 8 s timeout or any error, use the Apple engine and show the HUD "Used offline translation".

### 4.5 Menu bar
- **Icon:** an SF Symbol such as `doc.on.clipboard`. It changes while capture is paused.
- **Menu:** Open ClipDock, Pause capture (15 min / 1 hour / until resumed), Clear history… (asks for confirmation and deletes rows and blobs), Settings…, Quit.

### 4.6 Settings window
Keep it small, with these settings:
- shortcut recorders
- history limit and retention days
- ignored apps
- paste-all separator
- translation engine, API key, and model id
- launch at login
- **permission status:** Accessibility and Paste from Other Apps, each with an "Open Settings" button

### 4.8 Saved items and secrets (added 2026-11-11, Omar)
- The Pinned tab is now **Saved**. It holds pinned clips (⌘P), text Omar types in with ⌘N
  (an optional name, such as "Office address"), and secrets.
- **Secrets** (⌘N, then ⌘L): for passwords and API keys.
  - The value goes in the login **Keychain** only. The database row holds just the name and a
    Keychain reference, and the row shows dots instead of the value.
  - Pasting or copying one asks for Touch ID (or the Mac password) every time.
  - On the clipboard it's marked `org.nspasteboard.ConcealedType`, so clipboard managers skip
    it. After a paste the previous clipboard comes back at once; a copy is cleared after 30 s.
  - It's never translated, searched by value, joined in Paste all, or logged.
- Saved items never expire and survive Clear history. Deleting one asks first.
- The editor (⌘N, ⌘E) opens inside the popup in place of the list. Nothing else opens.

### 4.9 Clip actions (added 2026-11-11, Omar)
- **Row buttons:** under the pointer, a row shows ⋯ (the actions menu) and a trash button.
- **Actions menu** (⌘K, a right-click, or ⋯), with the actions that fit the item:
  - Paste; Paste as Plain Text (⌥↩, text with formatting) or Paste as Path (files)
  - Copy; Edit… (⌘E); Translate (⌘T, text only)
  - Open Link or Show in Finder (⌘O)
  - Add to Saved or Remove from Saved (⌘P)
  - Paste in UPPERCASE, Paste in lowercase, Paste without Extra Spaces (joins broken lines and
    squeezes spaces, keeping paragraphs). The cleaned-up text is added to history.
  - Delete (⌘⌫)
- In the menu, ↑↓ move, ↩ runs, and Esc closes only the menu.

### 4.7 Privacy rules
- All data stays local, and the app makes no network calls except in Claude mode.
- **Never log clipboard contents.** Logs may contain only ids, types, and sizes.

---

## 5. UI design language

This section comes from Omar's chosen reference, the 21st.dev "Toolbar Dock" by Ruixen UI: https://21st.dev/@ruixen.ui/components/toolbar-dock. That component is React. **Rebuild it natively in SwiftUI; don't embed it.**

**Omar owns the final layout.** Treat this section as the starting point and expect changes. Build the popup with plain styling first (M2–M4), then apply this section in M5 once Omar has confirmed the layout.

### 5.1 Look (values taken from the component's source)

**Dock pill**
- capsule shape, 48 pt tall, 8 pt padding
- 1 px hairline border
- background blur over a 95%-opaque background
- large soft shadow

**Icon buttons**
- 32 pt circles with 6 pt inner padding and a 2 pt gap between them
- icons with a 2 pt stroke (use SF Symbols with a matching weight)
- on hover, the circle fills with the accent color

**Badge**
- 8 pt dot in the top-right corner, inset 6 pt
- 1.7 pt ring in the background color

**Tooltip rail**
- **A single label surface** sits 12 pt above the dock. It is 32 pt tall with a 10 pt corner radius, uses inverted colors (light background, dark text), and has a large shadow.
- Text is 13 pt medium with −0.01em tracking, 12 pt horizontal padding, and an 8 pt gap before the keycaps.
- Keycap chips are 20 pt squares with a small radius and a 1 px border at 30% opacity, using 12 pt text.
- On hover, the rail **slides** sideways to sit above the hovered icon and **clips** itself so only that icon's label shows. It is one surface, not a separate tooltip for each icon.
- On the first hover, the rail appears in place without sliding. Later hovers slide.

**Toggle button**
- It stays pinned at the right end of the dock.
- Clicking it collapses the dock to just that button, with the icons sliding into it, and clicking again expands it. The toggle itself never moves.

### 5.2 Motion (use these exact values)

SwiftUI's `.interpolatingSpring(mass:stiffness:damping:)` uses the same spring physics as the Motion library, so these values carry over 1:1.

| Movement | mass | stiffness | damping |
|---|---|---|---|
| Tooltip slide (x) | 0.7 | 650 | 44 |
| Tooltip reveal / clip (no overshoot) | 0.7 | 720 | 52 |
| Collapse / expand width | 0.9 | 460 | 42 |

- **Fades:** 180 ms, `Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.18)`.
- **Reduce Motion:** when it's turned on, replace the springs with 120 ms fades.

### 5.3 Color tokens

These are approximately shadcn's "neutral" dark theme, which the reference uses. Dark is the default; light mode inverts them.

| Token | Dark |
|---|---|
| background | `#0A0A0A` at 95% + blur |
| foreground | `#FAFAFA` |
| border | white at 10% |
| accent (hover fill) | `#262626` |
| primary (tooltip background) | `#E5E5E5` |
| primary-foreground (tooltip text) | `#171717` |

### 5.4 Proposed popup layout (Omar may change this)

- **Structure:** the popup is the dock pill at the cursor, with a list card under it.
  - The card uses the same material, an 18 pt corner radius, and is about 360 pt wide.
  - Rows are 36 pt tall, with at most 8 visible.
- **Dock icons, left to right:** History, Saved (was Pinned, renamed 2026-11-11), Translate (⌘T), Paste all (⌘↩), Settings (⌘,). The toggle sits pinned at the right, and collapsing hides the list card so only the dock is left.
- **Tooltips:** each one shows the name and its shortcut chips, for example "Translate ⌘ T".
- **Selected row:** a soft filled capsule that slides between rows (`matchedGeometryEffect`) with the tooltip-slide spring.
- **HUDs** (Translating…, Copied, errors): a small pill at the cursor in the same material. It auto-dismisses after 600 ms, or after 1.5 s for errors.

---

## 6. Milestones

### M0 — Skeleton
- Check that Xcode is installed (`xcode-select -p`) and run `sw_vers`. Install XcodeGen.
- Create `project.yml`, a menu-bar app with an icon and Quit, and set `LSUIElement`.
- Set up stable signing (see gotcha 8.1).
- Write `./run.sh`. It runs `xcodegen generate`, then `xcodebuild`, then copies the app to `~/Applications/ClipDock.app` and relaunches it.

**Done when:**
- [ ] `./run.sh` builds the app and the menu-bar icon appears.
- [ ] A second rebuild still launches cleanly.
- [ ] The first git commit is made.

### M1 — Capture
- Build the pasteboard watcher, storage, dedupe, skip rules, retention, and the pasteboard-permission card.
- Temporarily, the menu shows the last 5 items so capture can be checked.

**Done when:**
- [ ] Text copied from 3 different apps, plus an image and a file, all appear.
- [ ] A password copied from a password manager does **not** appear.
- [ ] Quitting and relaunching keeps the history.
- [ ] Unit tests pass for dedupe, skip rules, and retention.

### M2 — Popup + paste
- Build the panel, the shortcut, cursor positioning, search, keyboard navigation, paste with ⌘V, and the Accessibility onboarding.
- Use plain styling.

**Done when:**
- [ ] ⌘⇧V near each screen corner, and on a second monitor if there is one, opens the popup fully on-screen.
- [ ] Typing filters the list.
- [ ] ↩ pastes into TextEdit, Notes, Chrome, and Slack.
- [ ] Esc and clicking outside both close the popup.
- [ ] The logged open time is under 100 ms.
- [ ] It works while the Russian keyboard layout is active.
- [ ] Unit tests pass for the positioning math, written as a pure function of the cursor and screen frames.

### M3 — Translation
- Build the `Translator` with the Apple engine, language detection, and language-pack onboarding.
- Add in-place translation, show-only translation, and ⌘T in the popup.

**Done when:**
- [ ] Selecting English in TextEdit and pressing ⌥⌘T replaces it with Russian.
- [ ] Russian becomes English the same way.
- [ ] ⌘Z restores the original text.
- [ ] The clipboard afterwards matches what it was before.
- [ ] Multi-paragraph text keeps its line breaks.
- [ ] ⇧⌥⌘T on a Safari page shows the card and doesn't paste.
- [ ] Unit tests pass for language detection and for paragraph splitting and rejoining.

### M4 — Pins, paste all, settings
- Add the Pinned section and ⌘P, multi-select with ⌘↩, the Settings window, launch at login, Pause capture, and Clear history.

**Done when:**
- [ ] A pinned item survives "Clear history".
- [ ] A unit test with a faked clock shows that pinned items survive the 30-day retention.
- [ ] Selecting 3 items and pressing ⌘↩ pastes them in the selected order, using the chosen separator.
- [ ] Every setting is still there after a relaunch.

### M5 — UI pass
- Before starting, **ask Omar to confirm or change section 5.4**.
- Apply section 5: the dock, the tooltip rail, the collapse toggle, the springs, the tokens, the HUDs, and Reduce Motion.

**Done when:**
- [ ] Omar signs off on how it looks and moves.
- [ ] The open time is still under 100 ms.

### M5b — Clip actions and Saved items (added 2026-11-11, Omar)
- Add the actions menu, the row buttons, the Saved tab with typed-in items and Keychain
  secrets, the editor, and the new popup keys (sections 3, 4.8, 4.9).

**Done when:**
- [ ] ⌘K and a right-click open the actions menu, and each action works.
- [ ] Hovering a row shows ⋯ and trash; deleting a saved item asks first.
- [ ] ⌘N saves a named item; with ⌘L it's a secret that pastes after Touch ID, and the
      clipboard afterwards matches what it was before.
- [ ] The secret's value is in the Keychain and nowhere in ClipDock's files or logs.
- [ ] ⌘E edits, then pastes (⌘↩) or saves (⌘S).
- [ ] Unit tests pass for the actions list, text clean-up, keymaps, and saved-item storage.

### M6 — Claude translation mode (optional)
- Add the Keychain-stored key, the engine choice, ⌃⌥⌘T, and the fallback to Apple.

**Done when:**
- [ ] With a key set, English becomes business Russian that uses "Вы".
- [ ] With Wi-Fi off, it falls back to Apple and shows the HUD.

---

## 7. Testing
- **Unit tests** (Swift Testing) for the pure logic: dedupe, skip rules, retention, language detection, text splitting, and positioning math.
- **Manual checks:** the "Done when" lists above.
- **Performance:** keep the `os_signpost` timing on the popup open path.

---

## 8. Known gotchas

1. **Permissions reset after every rebuild.**
   - **Cause:** macOS ties the Accessibility and Paste permissions to the app's code signature. Ad-hoc signing (`-`) changes on every build, so macOS forgets the permission.
   - **Fix:** sign with a stable certificate, and always run the copy in `~/Applications`.
   - **To get the certificate:** in Xcode, go to Settings → Accounts, add an Apple ID (free), then use Manage Certificates → "Apple Development".
2. **Paste prompts.** Read `accessBehavior` before polling (section 4.1).
3. **Secure input blocks synthetic keystrokes.** This affects password fields and terminals that have "Secure Keyboard Entry" on. Check `IsSecureEventInputEnabled()`. If it's on, copy instead of pasting and show the HUD "Can't paste here — copied instead".
4. **Electron apps and terminals** sometimes need a slightly longer delay before ⌘V. Keep the delay in one constant and tune it during M2.
5. **`.translationTask` sessions die with their view.** The hosting view must live as long as the app.
6. **Full-screen apps.** The panel needs `.fullScreenAuxiliary`, or it won't appear over them.

---

## 9. Out of scope
iCloud sync, other devices, the App Store, notarization, auto-update, OCR, and any AI features beyond translation.
