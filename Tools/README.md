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

Running the paste target as an app, so `open` brings it to the front:

```sh
T=/tmp/CDTarget.app; mkdir -p $T/Contents/MacOS
swiftc -O -o $T/Contents/MacOS/cdtool Tools/cdtool.swift
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string cdtool" -c "Add :CFBundleIdentifier string com.omar.clipdock.testtarget" -c "Add :CFBundlePackageType string APPL" $T/Contents/Info.plist
open -n $T --args target /tmp/out.txt --text /tmp/in.txt
```
