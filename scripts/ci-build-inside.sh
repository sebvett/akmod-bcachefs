#!/usr/bin/env bash
# Run inside a Fedora container. Builds the akmod SRPM and compiles one
# binary module against the container's kernel-devel, then checks modinfo.
set -euo pipefail
cd /work

dnf install -y --setopt=install_weak_deps=False \
  rpm-build kernel-devel gcc make elfutils-libelf-devel openssl-devel \
  kmodtool kmod zstd curl xz findutils

ver=$(awk '/^Version:/{print $2; exit}' packaging/bcachefs-kmod.spec)
kver=$(rpm -q kernel-devel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -1)
echo "Building bcachefs ${ver} against kernel ${kver}"

top=/work/artifacts/rpmbuild
rm -rf "$top" /work/artifacts/rpms
mkdir -p "$top"/{BUILD,BUILDROOT,RPMS,SRPMS,SOURCES,SPECS} /work/artifacts/rpms

tarball="bcachefs-tools-${ver}.tar.zst"
curl -fL --retry 3 -A 'akmod-bcachefs' -o "$top/SOURCES/${tarball}" \
  "https://evilpiepirate.org/bcachefs-tools/${tarball}"
cp packaging/bcachefs-kmod.spec "$top/SPECS/"

jobs=${JOBS:-2}
rpmbuild -ba \
  --define "_topdir $top" \
  --define "_smp_mflags -j${jobs}" \
  "$top/SPECS/bcachefs-kmod.spec"

rm -rf "$top/BUILD" "$top/BUILDROOT"
rpmbuild -bb \
  --define "_topdir $top" \
  --define "_smp_mflags -j${jobs}" \
  --define "kernels ${kver}" \
  "$top/SPECS/bcachefs-kmod.spec"

mapfile -t binary < <(find "$top/RPMS" -name 'kmod-bcachefs-*.rpm' ! -name 'akmod-*' | sort)
if [[ ${#binary[@]} -eq 0 ]]; then
  echo "No binary kmod RPM was produced" >&2
  find "$top/RPMS" -type f -print >&2
  exit 1
fi

inspect=$(mktemp -d)
(
  cd "$inspect"
  rpm2cpio "${binary[-1]}" | cpio -idmv
)
ko=$(find "$inspect" -name 'bcachefs.ko' -o -name 'bcachefs.ko.xz' | head -1)
if [[ -z $ko ]]; then
  echo "bcachefs.ko not found in ${binary[-1]}" >&2
  exit 1
fi

echo "---- modinfo ----"
modinfo "$ko"
got_version=$(modinfo -F version "$ko")
got_vermagic=$(modinfo -F vermagic "$ko")
got_alias=$(modinfo -F alias "$ko" | tr '\n' ' ')

[[ $got_version == "v${ver}" || $got_version == "$ver" ]] || {
  echo "version ${got_version} does not match ${ver}" >&2
  exit 1
}
[[ $got_vermagic == "${kver}"* ]] || {
  echo "vermagic ${got_vermagic} does not match ${kver}" >&2
  exit 1
}
[[ $got_alias == *fs-bcachefs* ]] || {
  echo "missing fs-bcachefs alias: ${got_alias}" >&2
  exit 1
}

cp -a "$top"/RPMS/*/*.rpm "$top"/SRPMS/*.src.rpm /work/artifacts/rpms/
echo "Compile test passed for ${ver} on ${kver}"
ls -l /work/artifacts/rpms
