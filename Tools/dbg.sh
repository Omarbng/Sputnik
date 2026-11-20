#!/bin/zsh
# Post a debug hook to Sputnik (debug build launched with
#   open --env CLIPDOCK_DEBUG_HOOKS=1 ~/Applications/Sputnik.app).
# Usage: Tools/dbg.sh <hook> [js-object-literal]
#   Tools/dbg.sh toggle
#   Tools/dbg.sh key '{keyCode: 125, command: false}'
#   Tools/dbg.sh query '{text: "hello"}'
#   Tools/dbg.sh state
#   Tools/dbg.sh focused '{text: "expected"}'
info="\$(${2:-})"
osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('com.omar.clipdock.debug.$1', 'test', $info, true); ''" >/dev/null
