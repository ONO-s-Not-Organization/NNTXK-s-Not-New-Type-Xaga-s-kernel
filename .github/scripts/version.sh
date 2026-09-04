#!/usr/bin/env bash
# KernelRelease := Version.PatchLevel.SubLevel-AndroidRelease-KmiGeneration-suffix
# Example: 5.10.66-android12-9-77777-g593c61caffd9-ab07212778
set -euo pipefail

if [[ -z "${ROOT:-}" ]]; then
  # shellcheck source=common.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
fi

ANDROID_RELEASE="${ANDROID_RELEASE:-android12}"
KMI_GENERATION="${KMI_GENERATION:-9}"
KERNEL_REPO_SLUG="${KERNEL_REPO_SLUG:-${GITHUB_REPOSITORY:-ONO-s-Not-Organization/NNTXK-s-Not-New-Type-Xaga-s-kernel}}"
VERSION_ENV="${VERSION_ENV:-${WORK_DIR}/version.env}"

is_shallow_repo() {
  git -C "${ROOT}" rev-parse --is-shallow-repository 2>/dev/null | grep -qx true
}

kernel_shortsha() {
  git -C "${ROOT}" rev-parse --short=12 HEAD
}

revcount_from_git() {
  git -C "${ROOT}" rev-list --count HEAD
}

revcount_from_api() {
  local sha url last
  sha="$(git -C "${ROOT}" rev-parse HEAD)"
  url="https://api.github.com/repos/${KERNEL_REPO_SLUG}/commits?sha=${sha}&per_page=1"
  last="$(
    curl -fsSIL \
      ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
      -H "Accept: application/vnd.github+json" \
      "${url}" \
      | tr -d '\r' \
      | awk 'tolower($1)=="link:" {print}' \
      | sed -n 's/.*[?&]page=\([0-9][0-9]*\).*rel="last".*/\1/p'
  )"
  if [[ -z "${last}" ]]; then
    # One page means 0 or 1 commit reachable via this endpoint.
    last="$(
      curl -fsSL \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
        -H "Accept: application/vnd.github+json" \
        "${url}" \
        | python3 -c 'import json,sys; data=json.load(sys.stdin); print(len(data))'
    )"
  fi
  [[ -n "${last}" && "${last}" != "0" ]] || return 1
  printf '%s\n' "${last}"
}

build_number() {
  local raw="${GITHUB_RUN_ID:-0}"
  if [[ ${#raw} -gt 8 ]]; then
    printf '%s\n' "${raw: -8}"
  else
    printf '%08d\n' "${raw}"
  fi
}

compute_kernel_release() {
  ensure_work_dir
  if [[ -f "${VERSION_ENV}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSION_ENV}"
    export LOCALVERSION KERNEL_RELEASE KERNEL_REVCOUNT KERNEL_SHORTSHA KERNEL_AB
    return 0
  fi
  if [[ -n "${KERNEL_RELEASE:-}" && -n "${LOCALVERSION:-}" && "${KERNEL_RELEASE}" == *-android12-9-*-g*-ab* ]]; then
    return 0
  fi

  if ! is_kernel_tree; then
    err "cannot compute KernelRelease outside the kernel tree"
    return 1
  fi

  local sha count ab
  sha="$(kernel_shortsha)"
  count=""
  if is_shallow_repo || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    count="$(revcount_from_api || true)"
  fi
  if [[ -z "${count}" ]]; then
    count="$(revcount_from_git)"
  fi
  ab="$(build_number)"

  export KERNEL_REVCOUNT="${count}"
  export KERNEL_SHORTSHA="${sha}"
  export KERNEL_AB="${ab}"
  export LOCALVERSION="-${ANDROID_RELEASE}-${KMI_GENERATION}-${count}-g${sha}-ab${ab}"
  export KERNEL_RELEASE="${KERNEL_VERSION}${LOCALVERSION}"

  cat > "${VERSION_ENV}" <<EOF
KERNEL_REVCOUNT=${KERNEL_REVCOUNT}
KERNEL_SHORTSHA=${KERNEL_SHORTSHA}
KERNEL_AB=${KERNEL_AB}
LOCALVERSION=${LOCALVERSION}
KERNEL_RELEASE=${KERNEL_RELEASE}
ANDROID_RELEASE=${ANDROID_RELEASE}
KMI_GENERATION=${KMI_GENERATION}
EOF

  write_github_output kernel_release "${KERNEL_RELEASE}"
  write_github_output localversion "${LOCALVERSION}"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    {
      echo "KERNEL_RELEASE=${KERNEL_RELEASE}"
      echo "KERNEL_REVCOUNT=${KERNEL_REVCOUNT}"
      echo "KERNEL_SHORTSHA=${KERNEL_SHORTSHA}"
      echo "KERNEL_AB=${KERNEL_AB}"
    } >> "${GITHUB_ENV}"
  fi
  log "KernelRelease=${KERNEL_RELEASE}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  compute_kernel_release
fi
