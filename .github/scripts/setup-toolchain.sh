#!/usr/bin/env bash
# Download the original clang-r416183b / gas / build-tools toolchains.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_cmd git
mkdir -p "${HOME}/toolchains"

if [[ ! -x "${CLANG_DIR}/bin/clang" ]]; then
  log "Cloning clang-r416183b"
  git clone --depth=1 \
    https://github.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r416183b \
    "${CLANG_DIR}"
fi

if [[ ! -d "${GAS_DIR}" ]]; then
  log "Cloning gas"
  git clone --depth=1 \
    https://android.googlesource.com/platform/prebuilts/gas/linux-x86 \
    "${GAS_DIR}"
fi

if [[ ! -d "${BUILD_TOOLS_DIR}" ]]; then
  log "Cloning build-tools"
  git clone --depth=1 \
    https://android.googlesource.com/platform/prebuilts/build-tools \
    "${BUILD_TOOLS_DIR}"
fi

export PATH="${CLANG_DIR}/bin:${BUILD_TOOLS_DIR}/path/linux-x86:${GAS_DIR}:${PATH}"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "CLANG_DIR=${CLANG_DIR}"
    echo "GAS_DIR=${GAS_DIR}"
    echo "BUILD_TOOLS_DIR=${BUILD_TOOLS_DIR}"
    echo "PATH=${PATH}"
  } >> "${GITHUB_ENV}"
fi
clang --version | head -n 2
log "Toolchain ready"
