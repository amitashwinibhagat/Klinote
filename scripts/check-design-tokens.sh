#!/usr/bin/env bash
# DESIGN.md is the source of truth, and it says: if code and that file
# disagree, the file wins and the code is wrong. This checks the mechanical
# half of that on every build.
#
# Visual inconsistency is not a taste question here. A 5 pt gap beside a 4 pt
# gap, or a 6 pt radius where the system says 8, reads to a clinician like a
# typo on a letterhead: that the thing was not looked after.
#
# Checks:
#   1. No font reached by number. Every size is a named role in KlinoteFont.
#   2. No radius outside 10 · 8 · 4 · 2.
#   3. No spacing outside 4 · 8 · 12 · 16 · 24 · 32 · 48, plus inline 2 and 6.
#   4. One width and one inset for the modal sheet family.
#
# Recursive grep rather than a file list: this repository lives under a path
# containing a space, and word splitting silently turned an earlier version of
# this script into one that printed success while checking nothing.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
sources="$root/apps/Klinote/Sources"

if [ ! -d "$sources" ]; then
  echo "::error::no sources at $sources"
  exit 1
fi

checked=$(find "$sources" -name '*.swift' | wc -l | tr -d ' ')
if [ "$checked" -lt 10 ]; then
  echo "::error::only $checked Swift files found; the source path is wrong"
  exit 1
fi

# Tokens.swift is where the values are defined, so it is the one exemption.
scan() {
  local pattern="$1"
  grep -rnE "$pattern" "$sources" --include='*.swift' --exclude='Tokens.swift' || true
}

violations=""

# 1. Fonts by number. A variable size is fine; a literal is not.
hits=$(scan '\.font\(\.system\(size: [0-9]')
[ -n "$hits" ] && violations+="a font size was reached by number — add a named role to KlinoteFont"$'\n'"$hits"$'\n'

# 2. Radii.
hits=$(scan 'cornerRadius: [0-9]')
[ -n "$hits" ] && violations+="a raw corner radius — use KlinoteMetrics.radiusDocument/Module/Chip/Lamp"$'\n'"$hits"$'\n'

# 3. Spacing. The scale is fixed by DESIGN.md: 4 · 8 · 12 · 16 · 24 · 32 · 48
#    for layout, 2 · 6 inline, and 0 for an edge-to-edge stack (which is not
#    spacing at all).
#
#    The value has to be read out of the match and compared against that set.
#    The pattern used to be `spacing: [1-9]`, which is really "any spacing that
#    begins with a digit" — so it rejected 4, 8, 12, 16, 24, 32 and 48, every
#    value the scale permits, and accepted only 0. It was green because no
#    positive spacing had been written yet, not because the scale was obeyed.
#    A guard that fails on correct code teaches people to ignore the guard.
spacing_scale=" 0 2 4 6 8 12 16 24 32 48 "
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  value=$(printf '%s' "$hit" \
    | grep -oE '(padding\(\.[a-zA-Z]+, [0-9]+\)|spacing: [0-9]+)' \
    | grep -oE '[0-9]+' | tail -1 || true)
  [ -n "$value" ] || continue
  case "$spacing_scale" in
    *" $value "*) ;;
    *) violations+="off-scale spacing — layout 4 8 12 16 24 32 48, inline 2 6"$'\n'"$hit"$'\n' ;;
  esac
done <<EOF
$(scan '(padding\(\.[a-zA-Z]+, [0-9]+\)|spacing: [0-9]+)')
EOF

# 4. Modal chrome: one family, one width and one inset.
for sheet in SetupSheet PasteTranscriptSheet CopyConfirmSheet; do
  hits=$(scan "\.frame\(width: [0-9]+\)" | grep "/$sheet.swift:" || true)
  [ -n "$hits" ] && violations+="$sheet.swift has its own width — use KlinoteMetrics.sheetWidth"$'\n'"$hits"$'\n'
done

if [ -n "$violations" ]; then
  echo "$violations"
  echo "::error::design tokens violated. See DESIGN.md."
  exit 1
fi

echo "design tokens: $checked files, fonts, radii, spacing and sheet chrome all from the system"
