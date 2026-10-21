#!/usr/bin/env bash
# The product claim is "nothing you record leaves this Mac". That claim is only
# worth making if it is checked on every build, so it lives here.
#
# There are exactly two named outbound paths in the app, and both are downloads:
#   1. the optional note model, in ModelDownloader.swift;
#   2. the OS speech asset install, in Transcriber.swift.
# Everything else in Sources must be free of network APIs. The Rust engine has
# no HTTP client at all.
#
# The guard lists the symbols it knows about and the exact file each may appear
# in. A new network path is a deliberate edit to this file, not a line that
# slips in under a different API name.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
sources="$root/apps/Klinote/Sources"
model="$sources/Core/ModelDownloader.swift"
transcriber="$sources/Core/Transcriber.swift"

fail() {
  echo "::error::$1"
  exit 1
}

# 1. Direct URL loading is the note-model download, in one file.
direct=$(grep -rlE 'URLSession|URLRequest|URLConnection' "$sources" | sort || true)
while IFS= read -r file; do
  [ -n "$file" ] || continue
  [ "$file" = "$model" ] || fail "URL loading outside ModelDownloader.swift: ${file#"$root"/}"
done <<< "$direct"

[ -f "$model" ] || fail "ModelDownloader.swift is missing"
grep -q 'URLSession' "$model" || fail "the note-model download disappeared without this check being updated"

# 2. The OS speech asset install is the only AssetInventory call, in one file.
asset=$(grep -rlE 'AssetInventory|downloadAndInstall' "$sources" | sort || true)
while IFS= read -r file; do
  [ -n "$file" ] || continue
  [ "$file" = "$transcriber" ] || fail "AssetInventory outside Transcriber.swift: ${file#"$root"/}"
done <<< "$asset"

# 3. Any other direct network primitive is refused outright, wherever it is.
other=$(grep -rlE 'NWConnection|NWListener|CFSocket|WebSocket|import Network|URLSessionUploadTask|uploadTask\(' "$sources" || true)
[ -z "$other" ] || fail "a network primitive appeared outside the two named download paths:
$other"

# 4. Nothing uploads, whatever it is called.
if grep -nE 'httpMethod[[:space:]]*=[[:space:]]*"(POST|PUT|PATCH|DELETE)"' "$model"; then
  fail "ModelDownloader.swift must only issue GET requests"
fi
if grep -nE 'URLSessionUploadTask|uploadTask\(' "$model"; then
  fail "an upload task appeared in ModelDownloader.swift"
fi

# 5. The engine keeps its own promise. A cargo failure is a failure, not a
# silent pass.
if ! deps=$(cd "$root" && cargo tree --workspace 2>&1); then
  fail "cargo tree failed, so the engine dependency check could not run:
$deps"
fi
if printf '%s\n' "$deps" | grep -Ei 'reqwest|hyper|ureq|isahc|surf|attohttpc|curl'; then
  fail "a networking crate entered the Rust dependency graph. See ADR 0002."
fi

echo "network surface: note model (GET) + OS speech asset in two named files; engine network-free"
