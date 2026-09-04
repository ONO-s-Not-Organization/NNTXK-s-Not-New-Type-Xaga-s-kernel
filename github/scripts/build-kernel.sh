#!/usr/bin/env bash
# Compile the already-configured kernel with the original author flags.
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
[[ -f "${OUT_DIR}/.config" ]] || { err "run apply-config.sh first"; exit 1; }

log "Building ${KERNEL_RELEASE} with timestamp ${KBUILD_BUILD_TIMESTAMP}"
kernel_make -j"$(nproc)" 2>&1 | tee "${WORK_DIR}/kernel.log"

IMAGE="${OUT_DIR}/arch/arm64/boot/Image"
IMAGE_GZ="${OUT_DIR}/arch/arm64/boot/Image.gz"
if [[ ! -f "${IMAGE}" && ! -f "${IMAGE_GZ}" ]]; then
  err "Build finished but Image is missing"
  exit 1
fi
log "Kernel image ready"
ls -l "${OUT_DIR}/arch/arm64/boot/Image"*
