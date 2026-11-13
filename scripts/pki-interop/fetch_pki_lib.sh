#!/usr/bin/env bash
# Fetches pki.sgit.ai's own modules at one released version (written once, never changed) and checks each
# file against the hash pinned here. The hashes are from https://pki.sgit.ai/lib/index.json, read on
# 13 November 2026. To move to a newer version, change VERSION and the five hashes together.
#
#   fetch_pki_lib.sh <folder to put them in>
set -euo pipefail
out=${1:?a folder to put the modules in}
VERSION=v0/v0.2/v0.2.28
mkdir -p "$out"
while read -r name hash; do
  curl -fsS --retry 3 -o "$out/$name" "https://pki.sgit.ai/lib/$VERSION/$name"
  got=$(sha256sum "$out/$name" | cut -d' ' -f1)
  if [ "$got" != "$hash" ]; then echo "::error::$name is $got, expected $hash"; exit 1; fi
  echo "$name $got"
done <<'HASHES'
keys.js 7c97cbd9dab3c3969b6bed4f24bce211c0406cee15c5a88458fec9fc5d48d143
message.js ad91e33ab9a711cad431bfc92f5610c5fe131e828a8e99450dbeccb1535b3b49
directory.js 7369832f63eb4b4fb5d3d820b2aa4b4f3287c37d03f8d5652942d13b186f1c53
delegation.js 0ecb7f7b9dc520550f147618927b5c3608125bcc801a719545e556c6dc984b6b
sso.js f250b6766e3f955081e7a8c562c77336bd81ffc13528c7f77f3d99b9b9052982
HASHES
