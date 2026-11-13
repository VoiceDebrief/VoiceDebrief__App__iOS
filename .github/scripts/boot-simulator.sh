#!/usr/bin/env bash
# Boot one simulator and wait for it, at most five minutes. `simctl bootstatus -b` can wait
# for ever on a fresh runner; xcodebuild finishes a slow boot itself, so after five minutes we
# stop waiting and let the test step carry on.
#
#   boot-simulator.sh <udid>
set -uo pipefail
u=${1:?udid}
xcrun simctl boot "$u" 2>/dev/null || true
( xcrun simctl bootstatus "$u" -b >/dev/null 2>&1 ) & p=$!
echo "booting simulator $u (a first boot on a fresh runner takes several minutes)"
for i in $(seq 1 60); do
  kill -0 "$p" 2>/dev/null || break
  sleep 5
  if [ $((i % 6)) -eq 0 ]; then echo "  still booting: $((i * 5)) s"; fi
done
if kill -0 "$p" 2>/dev/null; then echo "still booting after five minutes: carrying on"; kill "$p" 2>/dev/null || true; fi
xcrun simctl list devices | grep "$u" || true
exit 0
