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
  else
    echo "copying notes, models and templates"
    echo "  from $src_support"
    echo "  to   $dst_support"
    mkdir -p "$dst_support"
    ditto "$src_support" "$dst_support"
    # ditto exiting 0 is not proof the files landed.
    if [ -f "$src_support/klinote.sqlite" ] && [ ! -f "$dst_support/klinote.sqlite" ]; then
      echo "ditto reported success but the store is not at the destination"
      exit 1
    fi
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
  else
    echo "copying settings ($bundle_id.plist)"
    mkdir -p "$(dirname "$dst_prefs")"
    cp "$src_prefs" "$dst_prefs"
    if ! cmp -s "$src_prefs" "$dst_prefs"; then
      echo "prefs copy reported success but the files differ"
      exit 1
    fi
    copied=$((copied + 1))
  fi
fi

echo
"$(cd "$(dirname "$0")" && pwd)/observe.sh"
echo
if [ "$copied" -eq 0 ]; then
  # Nothing moved, so there is nothing to confirm and nothing to reclaim. The
  # first version printed the deletion command here too, which told anyone whose
  # copy was skipped to delete the only copy of whatever was in the old
  # location — the exact loss this script exists to prevent.
  echo "Nothing was copied, so nothing changed and nothing should be deleted."
  echo "Your data is still at:"
  echo "  $src_support"
  echo "  $src_prefs"
  echo
  echo "The container already has its own copy. If that copy is the newer one,"
  echo "leave both alone. If the old one is what you want, move the container's"
  echo "aside yourself first, then run this again."
  exit 0
fi

echo "Copied $copied item(s). The originals are still in place:"
echo "  $src_support"
echo "  $src_prefs"
echo
echo "Open Klinote, confirm your notes and name are there — and only then —"
echo "reclaim the space:"
echo "  rm -rf \"$src_support\" \"$src_prefs\""
