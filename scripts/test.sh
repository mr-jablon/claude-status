#!/bin/bash
# Runs `swift test`. With Command Line Tools only (no Xcode), SwiftPM does not find
# Testing.framework on its own, so point the compiler and linker at the CLT copy.
# CLT also ships _Testing_Foundation.framework without its module interface, so a file
# importing both Testing and Foundation fails unless cross-import overlays are disabled.
set -euo pipefail
cd "$(dirname "$0")/.."

FLAGS=()
if [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
    FLAGS=(-Xswiftc -F -Xswiftc "$F" -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F"
           -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays)
fi

# ${FLAGS[@]+...}: bash 3.2 (macOS) treats an empty array as unset under `set -u`.
exec swift test ${FLAGS[@]+"${FLAGS[@]}"} "$@"
