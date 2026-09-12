#!/usr/bin/env bash
# A Domain type that Tests mention must be mentioned in some Sources file
# other than the one that declares it.
#
# The declaring file always names the type. That does not count. A type that
# lives only in its own file plus Tests is a decision the product does not
# take — which is how Readiness and CopyGuard spent a week with nine green
# tests and no call site. Use from another Domain file counts: TaskViews is
# reached through TaskBoard, and that is a real path.
#
# Substring matches do not count (`rebuildTaskViews` is not `TaskViews`).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$root" <<'PY'
import re, sys
from pathlib import Path

root = Path(sys.argv[1])
src = root / "apps/Klinote/Sources"
tests_dir = root / "apps/Klinote/Tests"
domain = src / "Domain"

type_re = re.compile(r"^(?:public )?(?:enum|struct|actor|class)\s+(\w+)", re.M)

declared: dict[str, Path] = {}
for path in domain.rglob("*.swift"):
    for name in type_re.findall(path.read_text()):
        declared[name] = path


def mentions(path: Path, name: str) -> bool:
    return bool(re.search(rf"\b{name}\b", path.read_text()))


test_files = list(tests_dir.rglob("*.swift"))
src_files = list(src.rglob("*.swift"))

unwired: list[str] = []
tested = 0
for name, declared_in in sorted(declared.items()):
    if not any(mentions(p, name) for p in test_files):
        continue
    tested += 1
    used_elsewhere = any(
        mentions(p, name) for p in src_files if p.resolve() != declared_in.resolve()
    )
    if not used_elsewhere:
        unwired.append(name)

if unwired:
    print("unwired: tested in Domain, never mentioned outside the file that declares it:")
    for name in unwired:
        print(f"  {name}")
    print(
        "A passing test of a type the product does not use is not a test of the product."
    )
    sys.exit(1)

print(f"wired: {tested} tested Domain types are mentioned outside their declaring file")
PY
