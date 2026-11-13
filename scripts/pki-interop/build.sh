#!/usr/bin/env bash
# Compiles the app's own PKI source files, with the shared fixture checks, into one command-line tool for a Mac.
#   build.sh <output binary>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
app="$here/../../Apps/VoiceDebrief"
swiftc -O -o "${1:?output path}" \
  "$app/Sources/Engine/LaneCrypto.swift" \
  "$app/Sources/Engine/PKIKit.swift" \
  "$app/Sources/Model/IdentityVouch.swift" \
  "$app/Sources/Model/PKIDelegation.swift" \
  "$app/Tests/PKIFixtureChecks.swift" \
  "$here/main.swift"
