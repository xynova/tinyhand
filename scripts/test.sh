#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

# With only the Command Line Tools installed (no Xcode), SwiftPM can't find
# Swift Testing by itself, so point the compiler and linker at it.
args=()
clt=/Library/Developer/CommandLineTools
if [ "$(xcode-select -p 2>/dev/null)" = "$clt" ] && [ -d "$clt/Library/Developer/Frameworks/Testing.framework" ]; then
    frameworks="$clt/Library/Developer/Frameworks"
    args=(
        -Xswiftc -F -Xswiftc "$frameworks"
        -Xlinker -F -Xlinker "$frameworks"
        -Xlinker -rpath -Xlinker "$frameworks"
        -Xlinker -rpath -Xlinker "$clt/Library/Developer/usr/lib"
    )
fi

# One test at a time: the tests share TinyHand's picture cache (no lock) and the custom hands folder setting.
swift test --no-parallel ${args[@]+"${args[@]}"} "$@"
