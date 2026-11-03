#!/usr/bin/env bash
# Submit the built SRPMs (the akmod and, when built, upstream bcachefs-tools)
# to COPR. Fails when COPR_CONFIG is unset: publishing only runs on main, and a
# silent skip there leaves the test COPR to expire.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

if [[ -z ${COPR_CONFIG:-} ]]; then
  echo "COPR_CONFIG is not set, so nothing can be published." >&2
  echo "Store the copr-cli config file as the COPR_CONFIG Actions secret." >&2
  exit 1
fi

srpm=$(find artifacts -name 'bcachefs-kmod-*.src.rpm' -print | sort | tail -1)
if [[ -z $srpm ]]; then
  echo "No bcachefs-kmod SRPM under artifacts/" >&2
  exit 1
fi
srpms=("$srpm")
tools=$(find artifacts -name 'bcachefs-tools-*.src.rpm' -print | sort | tail -1)
if [[ -n $tools ]]; then
  srpms+=("$tools")
fi

install -d -m 0700 "${HOME}/.config"
umask 077
printf '%s\n' "$COPR_CONFIG" > "${HOME}/.config/copr"

if ! command -v copr-cli >/dev/null 2>&1 && ! command -v copr >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y copr-cli
  else
    sudo dnf install -y copr-cli
  fi
fi
if command -v copr-cli >/dev/null 2>&1; then
  copr=(copr-cli)
else
  copr=(copr)
fi

user=$(awk -F= '/^[[:space:]]*username[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "${HOME}/.config/copr")
project=${COPR_PROJECT:-akmod-bcachefs}
full="${user}/${project}"

# A test project deletes itself this many days after it was last refreshed.
# Empty keeps the project permanently.
days=${COPR_DELETE_AFTER_DAYS:-}
expiry=()
if [[ -n $days ]]; then
  expiry=(--delete-after-days "$days")
fi

if ! "${copr[@]}" get "$full" >/dev/null 2>&1; then
  echo "Creating COPR project ${full}"
  "${copr[@]}" create "$project" \
    --chroot fedora-44-x86_64 \
    "${expiry[@]}" \
    --unlisted-on-hp on \
    --description "akmod-bcachefs rebuilt from the bcachefs-tools DKMS sources" \
    --instructions "Enable this repo, then: rpm-ostree install akmod-bcachefs bcachefs-kmod-common"
fi

# Wait for the build so a COPR failure fails this job instead of passing silently.
echo "Submitting ${srpms[*]} to ${full}"
"${copr[@]}" build "$full" "${srpms[@]}"

if [[ -n $days ]]; then
  echo "Restarting the ${days}-day expiry of ${full}"
  "${copr[@]}" modify "$project" "${expiry[@]}"
fi
