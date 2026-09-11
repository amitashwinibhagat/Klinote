#!/usr/bin/env bash
# Developer entry points for the Local Clinical Scribe engine.
# Everything here is local: no model download, no network, no audio device.
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage: scripts/dev.sh <command>

  check      cargo check across the workspace
  test       run the full test suite (no model required)
  lint       clippy with warnings denied + rustfmt check
  fmt        apply rustfmt
  ci         check + lint + test, the same order CI runs
  templates  list the built-in note templates
  demo       generate a note from the synthetic fixture
  note       generate a note from a transcript:  scripts/dev.sh note <file>
  audit      show an audit trail:                scripts/dev.sh audit <db> <subject>

EOF
}

cmd="${1:-}"
shift || true

case "$cmd" in
  check)     cargo check --workspace --all-targets ;;
  test)      cargo test --workspace ;;
  lint)      cargo clippy --workspace --all-targets -- -D warnings && cargo fmt --all -- --check ;;
  fmt)       cargo fmt --all ;;
  ci)        cargo check --workspace --all-targets \
             && cargo clippy --workspace --all-targets -- -D warnings \
             && cargo fmt --all -- --check \
             && cargo test --workspace ;;
  templates) cargo run -q -p scribe-cli -- templates ;;
  demo)      cargo run -q -p scribe-cli -- note --transcript fixtures/sample-transcript.txt ;;
  note)      [ $# -ge 1 ] || { echo "usage: scripts/dev.sh note <transcript-file>" >&2; exit 2; }
             cargo run -q -p scribe-cli -- note --transcript "$1" ;;
  audit)     [ $# -ge 2 ] || { echo "usage: scripts/dev.sh audit <db> <subject>" >&2; exit 2; }
             cargo run -q -p scribe-cli -- audit --db "$1" --subject "$2" ;;
  ""|-h|--help|help) usage ;;
  *)         echo "unknown command: $cmd" >&2; usage; exit 2 ;;
esac
