#!/usr/bin/env bash
# Integrate KOWX712/KernelSU + official SUSFS. Any rejected hunk fails the job.
# Temporary clones are not committed.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_kernel_tree
need_cmd git
need_cmd patch
ensure_work_dir

if [[ -f "${REFS_FILE}" ]]; then
  saved_ksu="${KSU_REF:-}"
  saved_susfs="${SUSFS_REF:-}"
  # shellcheck disable=SC1090
  source "${REFS_FILE}"
  [[ -n "${saved_ksu}" ]] && KSU_REF="${saved_ksu}"
  [[ -n "${saved_susfs}" ]] && SUSFS_REF="${saved_susfs}"
fi

KSU_REF="${KSU_REF:?KSU_REF is required}"
SUSFS_REF="${SUSFS_REF:?SUSFS_REF is required}"

KSU_DIR="${WORK_DIR}/KernelSU"
SUSFS_DIR="${WORK_DIR}/susfs4ksu"

apply_patch() {
  local dir="$1" patch_file="$2" label="$3"
  log "Applying ${label}: ${patch_file}"
  (
    cd "${dir}"
    patch -p1 --forward --reject-file=- < "${patch_file}"
  )
}

# Full tree of the resolved SHA only (no sparse). Reuse dir on fallback.
fetch_sha() {
  local url="$1" dir="$2" sha="$3"
  if [[ ! -d "${dir}/.git" ]]; then
    rm -rf "${dir}"
    mkdir -p "${dir}"
    git -C "${dir}" init
    git -C "${dir}" remote add origin "${url}"
  fi
  git -C "${dir}" fetch --depth=1 origin "${sha}"
  git -C "${dir}" checkout --detach --force FETCH_HEAD
  git -C "${dir}" reset --hard FETCH_HEAD
  git -C "${dir}" clean -ffd
}

log "Fetching ${KSU_REPO} @ ${KSU_REF}"
fetch_sha "${KSU_CLONE_URL}" "${KSU_DIR}" "${KSU_REF}"

log "Fetching susfs4ksu ${SUSFS_BRANCH} @ ${SUSFS_REF}"
fetch_sha "${SUSFS_CLONE_URL}" "${SUSFS_DIR}" "${SUSFS_REF}"

cp -f "${SUSFS_DIR}/kernel_patches/fs/"* "${ROOT}/fs/"
cp -f "${SUSFS_DIR}/kernel_patches/include/linux/"* "${ROOT}/include/linux/"

ksu_patch="${SUSFS_DIR}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
kernel_patch="${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch"
[[ -f "${ksu_patch}" ]] || { err "missing ${ksu_patch}"; exit 1; }
[[ -f "${kernel_patch}" ]] || { err "missing ${kernel_patch}"; exit 1; }

apply_patch "${KSU_DIR}" "${ksu_patch}" "10_enable_susfs_for_ksu"
apply_patch "${ROOT}" "${kernel_patch}" "50_add_susfs_in_gki-android12-5.10"

rel="$(realpath --relative-to="${ROOT}/drivers" "${KSU_DIR}/kernel")"
ln -sfn "${rel}" "${ROOT}/drivers/kernelsu"
if ! grep -q 'kernelsu/' "${ROOT}/drivers/Makefile"; then
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "${ROOT}/drivers/Makefile"
fi
if ! grep -q 'drivers/kernelsu/Kconfig' "${ROOT}/drivers/Kconfig"; then
  sed -i '/^endmenu$/i source "drivers/kernelsu/Kconfig"' "${ROOT}/drivers/Kconfig"
fi

{
  echo "CHOSEN_KSU_REF=${KSU_REF}"
  echo "CHOSEN_SUSFS_REF=${SUSFS_REF}"
  echo "CHOSEN_PAIR_LABEL=${CHOSEN_PAIR_LABEL:-primary}"
} >> "${REFS_FILE}"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "CHOSEN_KSU_REF=${KSU_REF}"
    echo "CHOSEN_SUSFS_REF=${SUSFS_REF}"
    echo "CHOSEN_PAIR_LABEL=${CHOSEN_PAIR_LABEL:-primary}"
    echo "KSU_REF=${KSU_REF}"
    echo "SUSFS_REF=${SUSFS_REF}"
  } >> "${GITHUB_ENV}"
fi

log "Integrated KOW=${KSU_REF} SUSFS=${SUSFS_REF}"
