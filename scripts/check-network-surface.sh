#!/usr/bin/env bash
# The product claim is "nothing you record leaves this Mac". That claim is only
# worth making if it is checked on every build, so it lives here.
#
# Rules, in order of how badly they hurt if broken:
#   1. The Rust engine must have no HTTP client (also checked in ci.yml).
#   2. The macOS app may touch the network in exactly one file.
#   3. That file may only make GET requests — downloads, never uploads.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
sources="$root/apps/Klinote/Sources"

fail() {
  echo "::error::$1"
  exit 1
}

# 2. One file, named, and no others. Read line by line: this repository lives
# under a path containing a space, so word splitting would break it.
network_file=""
count=0
while IFS= read -r file; do
  [ -n "$file" ] || continue
  case "$file" in
    */Core/ModelDownloader.swift) ;;
    *) fail "network code outside ModelDownloader.swift: ${file#"$root"/}" ;;
  esac
  network_file="$file"
  count=$((count + 1))
done <<EOF
$(grep -rlE 'URLSession|URLRequest|URLConnection' "$sources" | sort)
EOF

if [ "$count" -eq 0 ]; then
  fail "no network file found — if URLSession was removed, update this check"
fi
if [ "$count" -gt 1 ]; then
  fail "$count files touch the network; expected exactly one"
fi

# 3. Downloads only.
if grep -nE 'httpMethod[[:space:]]*=[[:space:]]*"(POST|PUT|PATCH|DELETE)"' "$network_file"; then
  fail "ModelDownloader.swift must only issue GET requests"
fi
if grep -nE 'URLSessionUploadTask|uploadTask\(' "$network_file"; then
  fail "an upload task appeared in ModelDownloader.swift"
fi

# 1. Re-stated here so the claim is enforced by one script a reviewer can read.
if (cd "$root" && cargo tree --workspace 2>/dev/null | grep -Ei 'reqwest|hyper|ureq|isahc|surf|attohttpc|curl'); then
  fail "a networking crate entered the Rust dependency graph. See ADR 0002."
fi

echo "network surface: 1 file, GET only, engine network-free"
