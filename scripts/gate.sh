#!/usr/bin/env bash
# Every check, in one command, that fails loudly.
#
# This exists because the way these were being run by hand counted passes and
# never looked at failures:
#
#   cargo test --workspace | grep -oE "[0-9]+ passed" | awk '{s+=$1}'
#
# A failing doctest prints "test result: FAILED. 0 passed; 1 failed", and that
# pipeline still printed "80 Rust tests" — so a red build looked green, and a
# broken doc comment reached a release before CI caught it. Counting something
# is not checking it.
#
# Every step runs even when an earlier one fails, so one invocation tells you
# everything that is wrong rather than the first thing.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

failed=()

step() {
  local name="$1"
  shift
  printf '  %-24s' "$name"
  local output
  if output="$("$@" 2>&1)"; then
    printf 'ok\n'
  else
    printf 'FAILED\n'
    printf '%s\n' "$output" | tail -25 | sed 's/^/        /'
    failed+=("$name")
  fi
}

echo "gate"
step "rust format"   cargo fmt --all -- --check
step "rust clippy"   cargo clippy --workspace --all-targets -- -D warnings
step "rust tests"    cargo test --workspace
step "network surface" ./scripts/check-network-surface.sh
step "design tokens"   ./scripts/check-design-tokens.sh
step "swift tests"   bash -c '
  cd apps/Klinote || exit 1
  command -v xcodegen >/dev/null || { echo "xcodegen is not installed"; exit 1; }
  xcodegen generate >/dev/null || exit 1
  xcodebuild test \
    -project Klinote.xcodeproj \
    -scheme Klinote \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath /tmp/klinote-gate \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES
'

echo
if [ "${#failed[@]}" -eq 0 ]; then
  echo "all checks passed"
  exit 0
fi
echo "FAILED: ${failed[*]}"
exit 1
