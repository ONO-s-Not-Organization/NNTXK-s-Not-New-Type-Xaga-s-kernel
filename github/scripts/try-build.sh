#!/usr/bin/env bash
# Integrate + configure + compile. For latest, retry one aligned fallback pair.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_kernel_tree
ensure_work_dir

if [[ -f "${REFS_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${REFS_FILE}"
  set +a
fi

KSU_REF="${KSU_REF:?}"
SUSFS_REF="${SUSFS_REF:?}"
KSU_REF_IN="${KSU_REF_IN:-latest}"
SUSFS_REF_IN="${SUSFS_REF_IN:-latest}"

reset_tree() {
  log "Resetting kernel tree for fallback pair"
  git -C "${ROOT}" checkout -- \
    fs include/linux kernel mm security drivers \
    >/dev/null 2>&1 || true
  rm -f "${ROOT}/drivers/kernelsu"
  find "${ROOT}" -name '*.rej' -delete || true
  rm -rf "${OUT_DIR}"
}

run_pair() {
  local ksu="$1" susfs="$2" label="$3"
  export KSU_REF="${ksu}" SUSFS_REF="${susfs}" CHOSEN_PAIR_LABEL="${label}"
  log "Trying pair [${label}] KSU=${ksu} SUSFS=${susfs}"
  bash "${SCRIPT_DIR}/integrate.sh"
  bash "${SCRIPT_DIR}/apply-config.sh"
  bash "${SCRIPT_DIR}/build-kernel.sh"
}

use_fallback=0
if [[ "${KSU_REF_IN}" == "latest" && "${SUSFS_REF_IN}" == "latest" ]] \
  && [[ -n "${KSU_FALLBACK_TAG_SHA:-}" && -n "${SUSFS_FALLBACK_BUMP:-}" ]] \
  && { [[ "${KSU_FALLBACK_TAG_SHA}" != "${KSU_REF}" ]] || [[ "${SUSFS_FALLBACK_BUMP}" != "${SUSFS_REF}" ]]; }; then
  use_fallback=1
fi

if run_pair "${KSU_REF}" "${SUSFS_REF}" "primary"; then
  log "Primary pair built."
  exit 0
fi

if [[ "${use_fallback}" != "1" ]]; then
  err "Primary pair failed and fallback is not enabled (explicit refs)."
  exit 1
fi

reset_tree
if run_pair "${KSU_FALLBACK_TAG_SHA}" "${SUSFS_FALLBACK_BUMP}" "fallback"; then
  log "Fallback pair built (KOW ${KSU_FALLBACK_TAG:-} + SUSFS bump)."
  exit 0
fi

err "Both pairs failed."
exit 1
