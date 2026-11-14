#!/usr/bin/env bash
# Compiles the PKI source files (the SGitPeople package's key bundle and envelope, and the app's two register
# files), with the shared fixture checks, into one command-line tool for a Mac. One module: the app files'
# `import SGitPeople` is behind `#if canImport`, which is false here.
#   build.sh <output binary>
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
app="$here/../../Apps/VoiceDebrief"
people="$here/../../Packages/SGitPeople/Sources/SGitPeople"
swiftc -O -o "${1:?output path}" \
  "$people/LaneCrypto.swift" \
  "$people/PKIKit.swift" \
  "$app/Sources/Model/IdentityVouch.swift" \
  "$app/Sources/Model/PKIDelegation.swift" \
  "$app/Tests/PKIFixtureChecks.swift" \
  "$here/main.swift"
