# Own dictation ("ClipDock Voice") — plan (M7 write-up, 2026-11-19)

Omar wants his own Wispr Flow. This is the write-up M7 asked for: what it would take, how
good it can be, and what it can and can't match. **Nothing is built yet.**

## What Wispr Flow does (checked on wisprflow.ai, 2026-11-19)
- Hold a key (Fn), speak, release: the text appears in any app. Hands-free mode too.
- Detects 100+ languages automatically, including switching mid-speech.
- AI edits: removes "um"/"uh", adds punctuation, formats lists, handles "actually, make it 3pm".
- Personal dictionary (learns from your corrections), snippets ("my calendar link"), styles
  per app (formal for email, casual for chats), Command Mode (select text, say "make this
  shorter"), meeting notetaker, iPhone/Windows apps.
- Audio is processed in the cloud. Free up to 2,000 words a week, then a subscription.

## What this Mac can do on its own (probed 2026-11-19: M2, 16 GB, macOS 26.0)

| | English | French | Russian |
|---|---|---|---|
| `SpeechTranscriber` (Apple's new fast on-device model) | installed | installed | **not supported** |
| `DictationTranscriber` (Apple's older dictation model) | installed | supported | supported |
| Apple Intelligence on-device LLM (enabled on this Mac) | yes | yes | **no** |
| Vision text recognition (for screen/image commands) | yes | yes | yes |

Custom vocabulary exists in the SDK (`AnalysisContext.contextualStrings`). Apple's engines
need the language picked in advance; they don't detect it.

## Speech engines

| Engine | EN / FR / RU | Detects language | Download | New dependency |
|---|---|---|---|---|
| Apple `SpeechTranscriber` | ✓ / ✓ / ✗ | no | none (system) | no |
| Apple `DictationTranscriber` | ✓ / ✓ / ✓ | no | small (system) | no |
| NVIDIA Parakeet TDT v3 via FluidAudio (Core ML, Apache-2.0) | ✓ / ✓ / ✓ (25 European languages) | yes | roughly 0.5 GB | yes (ask Omar) |
| Whisper large-v3-turbo via WhisperKit (MIT) | ✓ / ✓ / ✓ (99 languages) | yes | roughly 1–1.6 GB | yes (ask Omar) |

**Recommendation:** start with Apple's engines (nothing to install). Then run a bake-off on
Omar's own voice — about 10 sentences per language, recorded and scored on the Mac — against
Parakeet v3. Adopt Parakeet only if it clearly wins. It probably will for Russian and for
mixing languages, because it detects the language by itself.

## Clean-up (Wispr's "AI edits")
1. **Rules, instant, all three languages:** drop fillers (um, uh / эм, ну, типа / euh, ben,
   bah), spoken punctuation ("new line", "новая строка", "à la ligne"), capitals, spacing.
2. **Apple Intelligence on-device model (English, French):** fix grammar, handle
   self-corrections, format lists, apply a style per app. Adds roughly half a second to a
   second. Free and private.
3. **Claude (optional, all languages, best quality):** only the text leaves the Mac, not the
   audio. Reuses the M6 Keychain key. Needed for top-quality Russian clean-up.

## How it would work inside ClipDock
- **Trigger:** hold a key to talk, release to insert. Double-tap the same key for hands-free;
  Esc cancels. ClipDock's double-tap monitor already watches modifier keys. Fn is taken by
  Wispr Flow and macOS, so the key is Omar's choice (right ⌥ held alone, right ⌘, or Fn if
  Wispr goes).
- **While speaking:** a small pill at the cursor (the HUD's material) with a live level meter
  and the volatile transcript.
- **Insert:** the same path as translation's Replace: save the clipboard, write, ⌘V, restore.
  Secure input falls back to "copied — press ⌘V".
- **History:** each dictation is saved in ClipDock with a "dictated" badge, so it's never lost
  when a paste misses (⌥⌥, ↩ to paste again).
- **Privacy:** audio stays in memory and is discarded after transcription; it's never written
  to disk or logged. Logs hold only durations, word counts and the engine name.
- **Permissions:** Microphone (new). Apple's engine may also ask for Speech Recognition.
  Accessibility is already granted.

## Beyond Wispr (things only ClipDock can easily do)
- **Speak one language, insert another:** say it in English and French or Russian appears,
  using the on-device translator ClipDock already has. Or speak Russian, get English.
- **Voice commands on selected text:** "translate to French", "make it formal", "shorter".
- **Voice snippets from Saved items:** "insert office address" pastes the Saved item of that
  name. Saved items already have names.
- No word limit, no account, works offline, and audio never leaves the Mac.

## What it can't match (honestly)
- **Polish:** Wispr runs large models in the cloud. On-device clean-up is good for English and
  French, but weaker on tricky rewrites, and there's no on-device model for Russian clean-up.
- **Learning from corrections automatically:** possible, but it means reading what Omar types
  after a dictation. Leave it out; add words to the dictionary by hand.
- iPhone and Windows apps, the meeting notetaker, team dictionaries, and very quiet "whisper"
  speech.

## Milestones (each one tried by Omar before the next)
- **D1 — Core loop:** hold → speak → release → text in any app, with the pill and the meter.
  Apple engines with a language picker (EN/FR via `SpeechTranscriber`, RU via
  `DictationTranscriber`). Saved to history. *Done when:* it works in Chrome, WhatsApp and
  Cursor in all three languages, and the text appears within about a second of release.
- **D2 — Engine bake-off:** Omar records the test sentences; compare word error rates; decide
  on Parakeet.
- **D3 — Clean-up and vocabulary:** filler and punctuation rules, Apple Intelligence clean-up
  (EN/FR), styles per app, a personal dictionary that feeds the recognizer, voice snippets.
- **D4 — Commands:** voice commands on selection, speak-and-translate, hands-free mode.

## Decisions Omar needs to make
1. Which key to hold.
2. Apple-only to start (recommended), or add Parakeet straight away (one dependency, about
   0.5 GB, automatic EN/FR/RU detection).
3. Clean-up on the Mac only, or Claude allowed for the best polish (text only, never audio).
4. Replace Wispr Flow, or run both (then they need different keys).

Tip before building: existing local Mac dictation apps (for example VoiceInk or Superwhisper)
run the same local models. Trying one for a day shows whether local accuracy is good enough
for Omar's voice and languages.
