# How Sputnik is built

A native macOS menu-bar app in Swift 6: SwiftUI for the views, AppKit for the panels, the menu
bar and keyboard events. Built with SwiftPM and the Command Line Tools (no Xcode project).

```
Sources/
  SputnikCore/        Pure logic and storage, no AppKit. Everything here has unit tests.
  Sputnik/            The app: windows, keys, clipboard, speech, translation.
Tests/SputnikCoreTests/
Resources/Info.plist
Vendor/KeyboardShortcuts/   A pinned copy of sindresorhus/KeyboardShortcuts
scripts/              run.sh, test.sh, release.sh, install.sh; dev/ has the test tools
docs/                 This file, PROGRESS.md (the build log), DICTATION.md, images/
```

## SputnikCore (logic)

| Folder | What's in it |
|---|---|
| `Models/` | `ClipItem` (a history row), `CapturedClip`, `ClipPayload` (text, link, image, files) |
| `Storage/` | `HistoryDatabase` (SQLite through GRDB), `BlobStore` (images on disk), `RetentionPolicy` |
| `Capture/` | `SkipRules`: what not to save (passwords, ignored apps, huge items) |
| `Search/` | `HistoryFilter`: search and the History / Saved / Secrets tabs |
| `Popup/` | Placement at the cursor, keymaps, the actions menu (`ClipAction`), paste stack |
| `Text/` | Link cleaning, sensitive-copy detection, contact and date detection, rewrite prompts, proofread checks |
| `Translation/` | `TranslationLanguage` (Apple's 20), `LanguageSetup` (someone's languages), `LanguageDetector`, text layout |
| `Dictation/` | Hold-to-talk detection, transcript picking, clean-up rules, voice commands, "say the language first" |
| `Hotkeys/` | Double-tap detection (⌥⌥, ⌃⌃, ⇧⇧) and the right-⌥ talk key |
| `Guide/` | What the Shortcuts window lists |

## Sputnik (app)

| Folder | What's in it |
|---|---|
| `App/` | Startup: wires everything together (`AppDelegate`) |
| `Capture/` | Watches the clipboard (every 0.3 s) and saves new copies |
| `Popup/` | The popup at the cursor: dock, list, actions menu, editor, Quick Look |
| `Paste/` | Writes to the clipboard and sends ⌘V / ⌘C; the paste stack |
| `Translation/` | Apple's on-device translator, the translation card, language downloads |
| `Dictation/` | Microphone, Apple's speech recognisers, the fn / right-⌥ keys, the dictation bar |
| `Writing/` | Apple Intelligence rewrites and the ⇧⇧ proofreader |
| `Images/` | Text in images, background removal, smaller images |
| `Saved/` | Saved snippets and Keychain secrets (Touch ID) |
| `Settings/`, `Setup/`, `Guide/` | The Settings window, the first-launch setup, the Shortcuts window |
| `Onboarding/`, `HUD/`, `MenuBar/`, `Design/` | Permission cards, small messages, the menu-bar icon, shared styles |
| `Debug/` | Test hooks, compiled into debug builds only and active only when asked for |

## Privacy rules the code follows

- Nothing leaves the Mac: Apple's on-device engines do translation, speech and writing.
- Logs hold ids, sizes, counts and timings, never what was copied or said.
- Audio stays in memory; secrets stay in the Keychain.

## Building

```sh
scripts/run.sh       # build, sign, install to ~/Applications, launch
scripts/test.sh      # unit tests
scripts/release.sh   # dist/Sputnik-<version>.dmg
```
