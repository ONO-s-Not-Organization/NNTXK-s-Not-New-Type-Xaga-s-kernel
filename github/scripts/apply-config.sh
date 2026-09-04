#!/usr/bin/env bash
# gki_defconfig + fragment. No menuconfig. Does not rewrite arch/arm64/configs/.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
# shellcheck source=version.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/version.sh"

require_kernel_tree
ensure_work_dir
compute_kernel_release
setup_kernel_env
need_cmd clang
need_cmd make

if [[ -f "${ROOT}/build.config.gki" ]]; then
  sed -i 's/check_defconfig//' "${ROOT}/build.config.gki"
fi

log "Configuring gki_defconfig (device kernel entry, not a GKI migration)"
kernel_make gki_defconfig

FRAGMENT="${CONFIG_DIR}/ksu-susfs.fragment"
[[ -f "${FRAGMENT}" ]] || { err "missing ${FRAGMENT}"; exit 1; }

if [[ -x "${ROOT}/scripts/kconfig/merge_config.sh" ]]; then
  "${ROOT}/scripts/kconfig/merge_config.sh" -m -O "${OUT_DIR}" \
    "${OUT_DIR}/.config" "${FRAGMENT}"
else
  cat "${FRAGMENT}" >> "${OUT_DIR}/.config"
fi

{
  printf 'CONFIG_LOCALVERSION="%s"\n' "${LOCALVERSION}"
  printf 'CONFIG_LOCALVERSION_AUTO=n\n'
} >> "${OUT_DIR}/.config"

kernel_make olddefconfig

if ! grep -q "^CONFIG_KSU=y" "${OUT_DIR}/.config" \
  || ! grep -q "^CONFIG_KSU_SUSFS=y" "${OUT_DIR}/.config" \
  || ! grep -q "^CONFIG_LOCALVERSION=\"${LOCALVERSION}\"" "${OUT_DIR}/.config"; then
  err "required config missing after olddefconfig"
  grep -E 'CONFIG_KSU|CONFIG_LOCALVERSION' "${OUT_DIR}/.config" || true
  exit 1
fi
if [[ "${KERNEL_RELEASE}" != ${KERNEL_VERSION}-android12-9-*-g*-ab* ]]; then
  err "KernelRelease does not match Version.PatchLevel.SubLevel-android12-9-suffix: ${KERNEL_RELEASE}"
  exit 1
fi
log "Kernel config ready at ${OUT_DIR}/.config"
