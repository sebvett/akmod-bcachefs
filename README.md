# akmod-bcachefs

Akmod packaging of the out-of-tree bcachefs module for Fedora Atomic
desktops (Aurora, Bluefin, Bazzite, Silverblue). DKMS cannot write
`/var/lib/dkms` during an `rpm-ostree` install. This package builds the
same module with akmods instead.

The module source is the DKMS tree in
[koverstreet/bcachefs-tools](https://github.com/koverstreet/bcachefs-tools).
The spec follows that repository's release tags and builds the upstream
C-only module (`BCACHEFS_RUST=0`). It does not fetch a precompiled module.

## What GitHub does

Two workflows:

- **Test akmod** runs on every pull request, on `main`, and daily. It
  builds the akmod in a Fedora 44 container and compiles a binary module
  against two kernels: Fedora's `kernel-devel` (`mainline`) and
  `kernel-longterm-devel` from the newest `kwizart/kernel-longterm-X.Y`
  COPR that builds for Fedora 44 (`longterm`, the kernel uCore's `lts`
  stream ships). Each build
  fails unless `modinfo` reports the expected version, vermagic, and
  `fs-bcachefs` alias. A green run on `main` (push, daily or manual)
  submits the source RPM to COPR and waits for the COPR build, so a
  failed COPR build fails the run. The same run builds upstream's own
  `bcachefs-tools.spec` and vendored tarball at the same version
  (`scripts/tools-srpm.sh`), so COPR carries tools that match the module.
- **Update from bcachefs-tools** runs every day. It reads the newest
  `vX.Y.Z` tag, checks that the matching tarball is on
  evilpiepirate.org, bumps the spec, and compile-tests it against both
  kernels. A passing test is pushed to `main`, and the next daily Test
  akmod run publishes it (pushes made with `GITHUB_TOKEN` do not start
  other workflows). A failing test opens a pull
  request and leaves `main` alone.

Until the `COPR_CONFIG` secret exists, the publish step logs a skip and
the compile test still runs. Publishing uses the test COPR project
`akmod-bcachefs-test` (override with the `COPR_PROJECT` repository
variable). The first publish creates that project unlisted, with a 14-day
lifetime (the `COPR_DELETE_AFTER_DAYS` default in `ci.yml`; remove it
there for a permanent project). Each publish restarts the countdown, so the project
only expires once publishing stops. List it, once you want
other people to find it, with:

```bash
copr-cli modify akmod-bcachefs --unlisted-on-hp off
```

The local `~/.config/copr` token expires on 2026-11-19. Renew it in COPR
and update the `COPR_CONFIG` secret when you do. The secret is the whole
config file, including the `login` and `token` lines.

## Install on Fedora Atomic

The published COPR is `sebvett/akmod-bcachefs-test` (the `COPR_PROJECT`
variable). After a publish has finished in COPR:

```bash
sudo dnf copr enable sebvett/akmod-bcachefs-test
sudo rpm-ostree install akmod-bcachefs bcachefs-kmod-common
systemctl reboot
```

On rpm-ostree the akmod's `%post` runs `akmods-ostree-post`, which builds
the module for every kernel in the new deployment and aborts the
transaction if a build fails. That needs the matching `kernel-devel` in
the deployment. Bazzite ships it in the image; on uCore `lts`, layer
`kernel-longterm-devel` at the image's kernel version from the
`kwizart/kernel-longterm-X.Y` COPR if the image lacks it.

`bcachefs-kmod-common` conflicts with `dkms-bcachefs`, so the DKMS
package is not layered alongside the akmod. Install `bcachefs-tools`
separately if you need the userspace utilities. After reboot:

```bash
modinfo -F version bcachefs
modinfo -F vermagic bcachefs
sudo modprobe bcachefs
```

This replaces the `sebvett/bcachefs-akmod-test` COPR. That project is not
updated by these workflows. An earlier `sebvett/akmod-bcachefs-test` was
deleted at the end of its 14-day test lifetime because nothing refreshed it.

## Local compile test

Requires podman or docker:

```bash
./scripts/ci-build.sh
```

RPMs land in `artifacts/rpms/`.
