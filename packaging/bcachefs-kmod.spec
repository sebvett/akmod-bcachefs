%global buildforkernels akmod
%global debug_package %{nil}

# Upstream dkms.conf.in sets BUILD_EXCLUSIVE_KERNEL_MIN=6.16.
%global min_kver 6.16

Name:           bcachefs-kmod
Version:        1.39.7
Release:        1%{?dist}
Summary:        Bcachefs filesystem kernel module
License:        GPL-2.0-only
URL:            https://github.com/koverstreet/bcachefs-tools

# Release tarball used by the upstream DKMS package. The non-vendored
# archive is enough: this package builds the C module only.
Source0:        https://evilpiepirate.org/bcachefs-tools/bcachefs-tools-%{version}.tar.zst

BuildRequires:  gcc
BuildRequires:  make
BuildRequires:  zstd
BuildRequires:  elfutils-libelf-devel
BuildRequires:  openssl-devel
BuildRequires:  kmodtool

# Packages required when akmods compiles this module on the target system.
%global AkmodsBuildRequires gcc, make, elfutils-libelf-devel, openssl-devel, zstd
%{expand:%(kmodtool --target %{_target_cpu} --repo rpmfusion --kmodname bcachefs %{?buildforkernels:--%{buildforkernels}} %{?kernels:--for-kernels "%{?kernels}"} 2>/dev/null)}

%description
Out-of-tree bcachefs filesystem module, packaged as an akmod.

bcachefs left the mainline kernel in 6.18. DKMS cannot write
/var/lib/dkms during an rpm-ostree install, so immutable Fedora
systems build this module with akmods instead. The module is the
upstream C build (BCACHEFS_RUST=0); it does not download a prebuilt
module.

%package common
Summary:        Common files for the bcachefs kernel module
BuildArch:      noarch
# Fedora and the ngompa COPR can pull dkms-bcachefs in beside bcachefs-tools.
# That package's %%post fails on rpm-ostree because it cannot write the DKMS tree.
Conflicts:      dkms-bcachefs

%description common
License and dependency anchor for the bcachefs akmod. Install this
together with akmod-bcachefs. Userspace bcachefs-tools is separate.

%files common
%license COPYING

%prep
%{?kmodtool_check}
%setup -q -n bcachefs-tools-%{version}

# install_dkms copies this helper into the module tree. A failing stub
# keeps the build on the packaged sources instead of fetching a prebuilt .ko.
printf '#!/bin/sh\nexit 1\n' > fs/scripts/fetch-module.sh
chmod 0755 fs/scripts/fetch-module.sh

make install_dkms VERSION=v%{version} DKMSDIR="$PWD/module" BCACHEFS_RUST=0
for kernel_version in %{?kernel_versions}; do
    cp -a module "_kmod_build_${kernel_version%%___*}"
done

%build
for kernel_version in %{?kernel_versions}; do
    make %{?_smp_mflags} -C "${kernel_version##*___}" \
        M="$PWD/_kmod_build_${kernel_version%%___*}" BCACHEFS_RUST=0 modules
done

%install
for kernel_version in %{?kernel_versions}; do
    install -D -m 0755 "_kmod_build_${kernel_version%%___*}/src/fs/bcachefs/bcachefs.ko" \
        "%{buildroot}%{kmodinstdir_prefix}/${kernel_version%%___*}/%{kmodinstdir_postfix}/bcachefs.ko"
done
%{?akmod_install}

%changelog
* Sun Oct 18 2026 Sebastian Vetterlein <sebvetterlein@outlook.com> - 1.39.7-1
- Package the out-of-tree DKMS module as an akmod for Fedora Atomic desktops
