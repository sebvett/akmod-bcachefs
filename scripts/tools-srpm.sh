#!/usr/bin/env bash
# Build the upstream bcachefs-tools SRPM at the akmod's version, from
# upstream's own bcachefs-tools.spec and vendored release tarball. Run in a
# Fedora container. The SRPM lands in artifacts/tools/.
#
# Upstream's spec uses its openSUSE Build Service sources unless _version is
# defined, and COPR rebuilds the SRPM without our --define, so the version is
# written into the spec instead.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

ver=$(awk '/^Version:/{print $2; exit}' packaging/bcachefs-kmod.spec)
top="$root/artifacts/tools-rpmbuild"
rm -rf "$top" artifacts/tools
mkdir -p "$top"/{SOURCES,SPECS} artifacts/tools

if ! command -v rpmbuild >/dev/null 2>&1; then
  dnf install -y --setopt=install_weak_deps=False rpm-build curl zstd
fi

spec=$(curl -fsSL --retry 3 \
  "https://raw.githubusercontent.com/koverstreet/bcachefs-tools/v${ver}/bcachefs-tools.spec")
# Two fixes to upstream's spec, both worth reporting upstream:
# - "Version: 0%{?_version}" yields 01.39.7 once _version is set.
# - The Rust build runs bindgen, which the spec does not BuildRequire.
if ! grep -q '^Version:[[:space:]]*0%{?_version}$' <<< "$spec" ||
   ! grep -q '^BuildRequires:[[:space:]]*clang-devel$' <<< "$spec"; then
  echo "Upstream spec changed shape; review this script" >&2
  exit 1
fi
{
  printf '%%global _version %s\n' "$ver"
  if grep -q 'bindgen' <<< "$spec"; then
    printf '%s\n' "$spec"
  else
    sed 's/^BuildRequires:[[:space:]]*clang-devel$/&\nBuildRequires:  bindgen-cli/' <<< "$spec"
  fi | sed 's/^Version:[[:space:]]*0%{?_version}$/Version:        %{_version}/'
} > "$top/SPECS/bcachefs-tools.spec"

tarball="bcachefs-tools-vendored-${ver}.tar.zst"
curl -fL --retry 3 -A 'akmod-bcachefs' -o "$top/SOURCES/${tarball}" \
  "https://evilpiepirate.org/bcachefs-tools/${tarball}"

rpmbuild -bs --nodeps \
  --define "_topdir $top" \
  "$top/SPECS/bcachefs-tools.spec"

cp "$top"/SRPMS/bcachefs-tools-*.src.rpm artifacts/tools/
ls -l artifacts/tools
