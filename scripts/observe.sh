#!/usr/bin/env bash
# The live artifacts the product actually reads.
#
# After any command that mutates preferences, the store, models, or anything
# outside this repo, run this and read the output before claiming the command
# worked. The command's exit code is not the outcome — `defaults delete
# one.klinote.mac` exits 0 while emptying the container's settings and leaving
# the old plist in place.
set -euo pipefail

bundle="one.klinote.mac"
container="$HOME/Library/Containers/$bundle/Data"
support="$container/Library/Application Support/Klinote"
prefs="$container/Library/Preferences/$bundle.plist"
legacy_support="$HOME/Library/Application Support/Klinote"
legacy_prefs="$HOME/Library/Preferences/$bundle.plist"

bytes() {
  if [ -f "$1" ]; then stat -f%z "$1"; else echo "-"; fi
}

present() {
  if [ -e "$1" ]; then echo present; else echo absent; fi
}

echo "observe (what the product reads, not what the command reported)"
if pgrep -x Klinote >/dev/null; then
  echo "  Klinote process:     running"
else
  echo "  Klinote process:     not running"
fi
echo "  container store:     $(bytes "$support/klinote.sqlite") bytes"
echo "  listening model:     $(bytes "$support/Models/ggml-small.en-tdrz.bin") bytes"
echo "  note model:          $(bytes "$support/Models/quire.gguf") bytes"
echo "  pre-sandbox data:    $(present "$legacy_support")"
echo "  pre-sandbox prefs:   $(present "$legacy_prefs")"
echo "  container prefs:"
if [ -f "$prefs" ]; then
  plutil -p "$prefs" | sed 's/^/    /'
else
  echo "    (no plist — the app will look like a first launch)"
fi
