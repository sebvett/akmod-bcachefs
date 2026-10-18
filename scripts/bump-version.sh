#!/usr/bin/env bash
# Point the spec at a bcachefs-tools release. Usage: bump-version.sh 1.39.8
set -euo pipefail

if [[ $# -ne 1 || ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 <x.y.z>" >&2
  exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
spec="$root/packaging/bcachefs-kmod.spec"
new=$1
old=$(awk '/^Version:/{print $2; exit}' "$spec")

if [[ $old == "$new" ]]; then
  echo "Spec is already at ${new}"
  exit 0
fi

python3 - "$spec" "$old" "$new" <<'PY'
import re
import sys
from datetime import datetime, timezone

path, old, new = sys.argv[1:]
text = open(path).read()
text2, n = re.subn(
    rf"^Version:\s+{re.escape(old)}\s*$",
    f"Version:        {new}",
    text,
    count=1,
    flags=re.M,
)
if n != 1:
    sys.exit(f"could not replace Version: {old}")
text2, n = re.subn(
    r"^Release:\s+\d+",
    "Release:        1",
    text2,
    count=1,
    flags=re.M,
)
if n != 1:
    sys.exit("could not reset Release")
stamp = datetime.now(timezone.utc).strftime("%a %b %d %Y")
entry = (
    f"* {stamp} github-actions <github-actions@github.com> - {new}-1\n"
    f"- Update to bcachefs-tools {new}\n\n"
)
needle = "%changelog\n"
if needle not in text2:
    sys.exit("spec has no %changelog")
text2 = text2.replace(needle, needle + entry, 1)
open(path, "w").write(text2)
print(f"Bumped {old} -> {new}")
PY
