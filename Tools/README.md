# Test tools (development only, not part of the app)

- `dbg.sh`: drives a debug build through its debug hooks (see `Sources/ClipDock/Debug/DebugHooks.swift`).
  The hooks load only when ClipDock is launched with `open --env CLIPDOCK_DEBUG_HOOKS=1 ~/Applications/ClipDock.app`.
- `cdtool.swift`: build with `swiftc -O -o /tmp/cdtool Tools/cdtool.swift`. It reads and sets the keyboard
  layout, reads and moves the mouse, lists screens, and opens a paste-target window (optionally with
  secure input on).
- `clip-save.js` / `clip-restore.js`: save and restore the whole clipboard (every item and type) around a
  test, with `osascript -l JavaScript Tools/clip-save.js /path/file.json`.

Before a test sends ⌘V, it must check that the intended app is frontmost. Otherwise the paste lands in
whatever you're using at that moment.

**Omar uses the Mac while tests run.** Keystrokes and pastes go to whatever app is frontmost when they're
delivered, so a check made a moment earlier in a script isn't enough. Rules since 2026-11-11:

- Drive the popup with the in-app hooks (`key`, `action`, `editor`, `editorSet`, `fieldCommand`, `query`).
  They call the popup directly and post nothing to the system. The `postKey`/`postText`/`postMouse`
  hooks do post real events: use them only when nobody is at the Mac.
- The hooks that open UI or can paste are refused unless the test target app
  (`com.omar.clipdock.testtarget`) is frontmost. Posting hooks also need the popup to be key.
- Use a test build for anything that pastes: `CLIPDOCK_TEST_BUILD=1 ./run.sh`, then
  `open --env CLIPDOCK_DEBUG_HOOKS=1 --env CLIPDOCK_TEST_TARGET_ONLY=1 --env CLIPDOCK_FAKE_AUTH=1 ~/Applications/ClipDock.app`.
  It sends ⌘V/⌘C only while the test target is frontmost (checked right before sending), and
  `CLIPDOCK_FAKE_AUTH=1` skips Touch ID for secrets. **Reinstall the everyday build (`./run.sh`) afterwards.**
- Run bursts only after the Mac has been idle for a minute:
  `ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'`.
- Posted Unicode-only key events are ignored by a freshly focused text field until one real key-code event
  reaches it; send a harmless → first. (A physical keyboard always sends key codes.)

Running the paste target as an app, so `open` brings it to the front:

```sh
T=/tmp/CDTarget.app; mkdir -p $T/Contents/MacOS
swiftc -O -o $T/Contents/MacOS/cdtool Tools/cdtool.swift
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string cdtool" -c "Add :CFBundleIdentifier string com.omar.clipdock.testtarget" -c "Add :CFBundlePackageType string APPL" $T/Contents/Info.plist
open -n $T --args target /tmp/out.txt --text /tmp/in.txt
```
