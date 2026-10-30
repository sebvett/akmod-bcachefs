#!/usr/bin/env bash
# Run inside a Fedora container. Builds the akmod SRPM and compiles one
# binary module against the container's kernel-devel, then checks modinfo.
# KERNEL_FLAVOR=mainline uses Fedora's kernel-devel. KERNEL_FLAVOR=longterm
# uses kernel-longterm-devel from the newest kwizart/kernel-longterm-X.Y COPR
# that builds for this Fedora release, the kernel uCore's lts stream ships.
set -euo pipefail
cd /work

flavor=${KERNEL_FLAVOR:-mainline}
case $flavor in
  mainline)
    devel=kernel-devel
    ;;
  longterm)
    devel=kernel-longterm-devel
    dnf install -y --setopt=install_weak_deps=False dnf-plugins-core jq
    chroot="fedora-$(rpm -E %fedora)-$(uname -m)"
    project=$(curl -fsSL --retry 3 \
      "https://copr.fedorainfracloud.org/api_3/project/list?ownername=kwizart&limit=1000" \
      | jq -r --arg chroot "$chroot" '.items[]
          | select((.name | test("^kernel-longterm-[0-9]+\\.[0-9]+$")) and (.chroot_repos | has($chroot)))
          | .name' \
      | sort -V | tail -1)
    if [[ -z $project ]]; then
      echo "No kwizart/kernel-longterm-X.Y COPR builds for ${chroot}" >&2
      exit 1
    fi
    echo "Using kwizart/${project}"
    dnf copr enable -y "kwizart/${project}"
    ;;
  *)
    echo "unknown KERNEL_FLAVOR ${flavor}" >&2
    exit 2
    ;;
esac

dnf install -y --setopt=install_weak_deps=False \
  rpm-build "$devel" gcc make elfutils-libelf-devel openssl-devel \
  kmodtool kmod zstd curl xz findutils

ver=$(awk '/^Version:/{print $2; exit}' packaging/bcachefs-kmod.spec)
kver=$(rpm -q "$devel" --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -1)
echo "Building bcachefs ${ver} against ${flavor} kernel ${kver}"

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
echo "Compile test passed for ${ver} on ${flavor} kernel ${kver}"
ls -l /work/artifacts/rpms
