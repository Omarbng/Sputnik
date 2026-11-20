#!/bin/zsh
# Post a debug hook to Sputnik (debug build launched with
#   open --env CLIPDOCK_DEBUG_HOOKS=1 ~/Applications/Sputnik.app).
# Usage: scripts/dev/dbg.sh <hook> [js-object-literal]
#   scripts/dev/dbg.sh toggle
#   scripts/dev/dbg.sh key '{keyCode: 125, command: false}'
#   scripts/dev/dbg.sh query '{text: "hello"}'
#   scripts/dev/dbg.sh state
#   scripts/dev/dbg.sh focused '{text: "expected"}'
info="\$(${2:-})"
osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('com.omar.clipdock.debug.$1', 'test', $info, true); ''" >/dev/null
