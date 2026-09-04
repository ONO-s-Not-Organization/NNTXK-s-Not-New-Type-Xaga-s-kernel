#!/usr/bin/env bash
# KernelRelease := 5.10.66-android12-9-114514-g<12sha>-ab<full run_id>
set -euo pipefail

if [[ -z "${ROOT:-}" ]]; then
  # shellcheck source=common.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
fi

ANDROID_RELEASE="${ANDROID_RELEASE:-android12}"
KMI_GENERATION="${KMI_GENERATION:-9}"
VERSION_ENV="${VERSION_ENV:-${WORK_DIR}/version.env}"
FIXED_REV="114514"

kernel_shortsha() {
  git -C "${ROOT}" rev-parse --short=12 HEAD
}

build_number() {
  printf '%s\n' "${GITHUB_RUN_ID:-0}"
}

compute_kernel_release() {
  ensure_work_dir
  if [[ -f "${VERSION_ENV}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSION_ENV}"
    export LOCALVERSION KERNEL_RELEASE KERNEL_REVCOUNT KERNEL_SHORTSHA KERNEL_AB
    return 0
  fi
  if [[ -n "${KERNEL_RELEASE:-}" && -n "${LOCALVERSION:-}" && "${KERNEL_RELEASE}" == *-android12-9-114514-g*-ab* ]]; then
    return 0
  fi

  if ! is_kernel_tree; then
    err "cannot compute KernelRelease outside the kernel tree"
    return 1
  fi

  local sha ab
  sha="$(kernel_shortsha)"
  ab="$(build_number)"

  export KERNEL_REVCOUNT="${FIXED_REV}"
  export KERNEL_SHORTSHA="${sha}"
  export KERNEL_AB="${ab}"
  export LOCALVERSION="-${ANDROID_RELEASE}-${KMI_GENERATION}-${FIXED_REV}-g${sha}-ab${ab}"
  export KERNEL_RELEASE="${KERNEL_VERSION}${LOCALVERSION}"

  if [[ ${#KERNEL_RELEASE} -gt 64 ]]; then
    err "KERNELRELEASE exceeds 64 characters: ${KERNEL_RELEASE} (${#KERNEL_RELEASE})"
    return 1
  fi

  cat > "${VERSION_ENV}" <<EOF
KERNEL_REVCOUNT=${KERNEL_REVCOUNT}
KERNEL_SHORTSHA=${KERNEL_SHORTSHA}
KERNEL_AB=${KERNEL_AB}
LOCALVERSION=${LOCALVERSION}
KERNEL_RELEASE=${KERNEL_RELEASE}
ANDROID_RELEASE=${ANDROID_RELEASE}
KMI_GENERATION=${KMI_GENERATION}
EOF

  log "KernelRelease=${KERNEL_RELEASE}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  compute_kernel_release
fi
