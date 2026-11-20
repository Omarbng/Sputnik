# Sputnik

**Your clipboard, your voice and translation, at your cursor.** A small macOS menu-bar app.
Everything runs on your Mac: no account, no cloud, no tracking.

**[⬇︎ Download for macOS](../../releases/latest)**: get the `.dmg` and drag Sputnik to Applications.

## What it does

- **Clipboard history at your cursor:** tap ⌥ twice. Search, paste, paste several at once,
  save snippets, keep secrets behind Touch ID. Copied links lose their tracking junk;
  passwords and one-time codes you copy disappear after 10 minutes.
- **Talk instead of typing:** hold fn, speak, let go, and it's typed where you are. Tap ⇧
  while talking to type it in another language; tap ⌃ to tell it what to do with the selected
  text ("make it shorter", "translate to German"). Hold right ⌥ if you prefer.
- **Translate and proofread anywhere:** select text in any app, tap ⌃ twice to translate it,
  ⇧ twice to proofread it in place.
- **More in ⌘K:** text from images, background removal, smaller images, WhatsApp, call, email
  or add to Calendar when the text has a number, address or date.
- **Your languages:** pick any of the 20 languages Apple translates on the Mac (Arabic, Chinese,
  Dutch, English, French, German, Hindi, Indonesian, Italian, Japanese, Korean, Polish,
  Portuguese, Russian, Spanish, Thai, Turkish, Ukrainian, Vietnamese) and up to three to dictate in.

Menu bar → **Shortcuts…** lists every key and voice command.

## Install

1. Download `Sputnik-x.y.z.dmg` from [Releases](../../releases/latest) and drag **Sputnik** to
   **Applications**.
2. Open it. Sputnik isn't notarized by Apple, so macOS stops it the first time: open
   **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**. You do this
   once per download.
3. The **Welcome to Sputnik** setup walks you through your languages and three permissions:
   Accessibility (for the shortcuts and pasting), Paste from Other Apps (choose **Allow**), and
   the microphone (only while you hold fn).
4. To dictate with fn, set **System Settings → Keyboard → Press 🌐 key to → Do Nothing**.

**Needs:** macOS 26 or later on an Apple Silicon Mac. Proofreading, rewriting and dictation polish
use Apple Intelligence when it's turned on; everything else works without it.

## Privacy

- Clipboard history lives in `~/Library/Application Support/ClipDock` on your Mac. Secrets are in
  your Keychain.
- Translation, speech recognition and writing tools are Apple's on-device engines. Language
  files are downloaded from Apple once.
- Audio stays in memory and is dropped once it's turned into text.
- Logs hold counts, sizes and timings, never what you copied or said.

## Build from source

You need the Command Line Tools (`xcode-select --install`) with Swift 6.2.

```sh
git clone <this repository>
cd <its folder>
./run.sh          # builds, signs, installs to ~/Applications and launches
./test.sh         # unit tests
./release.sh      # a signed .dmg in dist/
```

Builds are signed with the certificate named in `SIGN_IDENTITY` (default "ClipDock Dev"). Without
it, `run.sh` signs ad hoc, and macOS asks for the permissions again after every build. Make a
self-signed code-signing certificate in Keychain Access (Certificate Assistant → Create a
Certificate → Code Signing) to keep them.

## Licence

MIT. See [LICENSE](LICENSE).
