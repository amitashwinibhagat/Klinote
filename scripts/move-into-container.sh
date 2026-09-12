#!/usr/bin/env bash
# Move a pre-sandbox Klinote install into its container.
#
# 0.1.x stored everything in ~/Library/Application Support/Klinote and its
# settings in ~/Library/Preferences/one.klinote.mac.plist. A sandboxed build
# cannot read either — the sandbox is the thing that stops it — so both have to
# be brought across once, from outside the app. There is no way to do this from
# inside: an app that could reach outside its container to migrate itself would
# not be sandboxed.
#
# Per item, and only into a destination that does not exist yet. Nothing is ever
# overwritten, so running it twice is harmless and running it after the app has
# already written a note cannot destroy that note. The originals are left in
# place: a mistake costs disk space, not records. The models alone are 2 GB that
# a re-download would charge for twice.
set -euo pipefail

bundle_id="one.klinote.mac"
container="$HOME/Library/Containers/$bundle_id/Data"
src_support="$HOME/Library/Application Support/Klinote"
dst_support="$container/Library/Application Support/Klinote"
src_prefs="$HOME/Library/Preferences/$bundle_id.plist"
dst_prefs="$container/Library/Preferences/$bundle_id.plist"

copied=0
skipped=0

if [ ! -d "$src_support" ] && [ ! -f "$src_prefs" ]; then
  echo "nothing to move: no $src_support and no $src_prefs"
  exit 0
fi

# ditto, not cp -R: it preserves resource forks, extended attributes and
# permissions, and it is the tool that round-trips these correctly.
if [ -d "$src_support" ]; then
  if [ -d "$dst_support" ] && [ -n "$(ls -A "$dst_support" 2>/dev/null)" ]; then
    echo "skipped: the container already has notes and models"
    echo "         $dst_support"
    skipped=$((skipped + 1))
  else
    echo "copying notes, models and templates"
    echo "  from $src_support"
    echo "  to   $dst_support"
    mkdir -p "$dst_support"
    ditto "$src_support" "$dst_support"
    copied=$((copied + 1))
  fi
fi

# Settings move too, and they are the easy thing to forget: a sandboxed app
# reads its preferences from the container. Without this the clinician's name,
# registration number and retention policy silently revert to defaults — the
# state that looks like the app has forgotten who you are.
if [ -f "$src_prefs" ]; then
  if [ -f "$dst_prefs" ]; then
    echo "skipped: settings already present in the container"
    skipped=$((skipped + 1))
  else
    echo "copying settings ($bundle_id.plist)"
    mkdir -p "$(dirname "$dst_prefs")"
    cp "$src_prefs" "$dst_prefs"
    copied=$((copied + 1))
  fi
fi

echo
if [ "$skipped" -gt 0 ]; then
  echo "Nothing was overwritten. If a skip is wrong, move the container copy"
  echo "aside yourself and run this again — but do that knowing it replaces"
  echo "whatever the app has written since."
  echo
fi
echo "The originals are still in place:"
echo "  $src_support"
echo "  $src_prefs"
echo
echo "Open Klinote, confirm your notes and name are there, then reclaim the"
echo "space:"
echo "  rm -rf \"$src_support\" \"$src_prefs\""
