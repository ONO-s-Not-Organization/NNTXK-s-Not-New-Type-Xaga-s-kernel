#!/usr/bin/env bash
# Shared constants for the xagapro 5.10.66 CI overlay.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export ROOT SCRIPT_DIR
CONFIG_DIR="${CONFIG_DIR:-${SCRIPT_DIR}/../config}"

DEVICE="${DEVICE:-xagapro}"
KERNEL_VERSION="${KERNEL_VERSION:-5.10.66}"
ANDROID_RELEASE="${ANDROID_RELEASE:-android12}"
KMI_GENERATION="${KMI_GENERATION:-9}"
LOCALVERSION="${LOCALVERSION:-}"
KERNEL_RELEASE="${KERNEL_RELEASE:-}"

KSU_REPO="${KSU_REPO:-KOWX712/KernelSU}"
KSU_CLONE_URL="${KSU_CLONE_URL:-https://github.com/${KSU_REPO}.git}"
SUSFS_CLONE_URL="${SUSFS_CLONE_URL:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_BRANCH="${SUSFS_BRANCH:-gki-android12-5.10}"

export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-Fri Sep 1 00:00:00 CST 2023}"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-xagapro}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-github-actions}"
export TZ="${TZ:-Asia/Hong_Kong}"

CLANG_DIR="${CLANG_DIR:-${HOME}/toolchains/clang-r416183b}"
GAS_DIR="${GAS_DIR:-${HOME}/toolchains/gas/linux-x86}"
BUILD_TOOLS_DIR="${BUILD_TOOLS_DIR:-${HOME}/toolchains/build-tools}"

OUT_DIR="${OUT_DIR:-${ROOT}/out}"
WORK_DIR="${WORK_DIR:-${ROOT}/.ci-work}"
REFS_FILE="${REFS_FILE:-${WORK_DIR}/resolved-refs.env}"
BUILD_INFO="${BUILD_INFO:-${WORK_DIR}/build-info.json}"

log() { printf '[+] %s\n' "$*"; }
err() { printf '[!] %s\n' "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "missing command: $1"; exit 1; }
}

ensure_work_dir() {
  mkdir -p "${WORK_DIR}" "${OUT_DIR}"
}

is_kernel_tree() {
  [[ -f "${ROOT}/Makefile" ]] && grep -q '^VERSION = 5$' "${ROOT}/Makefile"
}

require_kernel_tree() {
  if ! is_kernel_tree; then
    err "This overlay must live in the kernel fork root (Makefile VERSION = 5)."
    exit 1
  fi
}

write_github_output() {
  local key="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      printf '%s<<EOF\n' "${key}"
      printf '%s\n' "${value}"
      printf 'EOF\n'
    } >> "${GITHUB_OUTPUT}"
  fi
}

setup_kernel_env() {
  export ARCH=arm64
  export SUBARCH=arm64
  export LLVM=1
  export LLVM_IAS=1
  export CLANG_TRIPLE=aarch64-linux-gnu-
  export CROSS_COMPILE=aarch64-linux-gnu-
  export KBUILD_BUILD_TIMESTAMP KBUILD_BUILD_USER KBUILD_BUILD_HOST TZ
  if [[ -d "${CLANG_DIR}/bin" ]]; then
    export PATH="${CLANG_DIR}/bin:${PATH}"
  fi
  if [[ -d "${BUILD_TOOLS_DIR}/path/linux-x86" ]]; then
    export PATH="${BUILD_TOOLS_DIR}/path/linux-x86:${PATH}"
  fi
  if [[ -d "${GAS_DIR}" ]]; then
    export PATH="${GAS_DIR}:${PATH}"
  fi
}

kernel_make() {
  local -a cmd=(make ARCH=arm64 LLVM=1 LLVM_IAS=1 O="${OUT_DIR}")
  if command -v ccache >/dev/null 2>&1; then
    cmd+=(CC="ccache clang" CXX="ccache clang++")
    export CCACHE_DIR="${CCACHE_DIR:-${HOME}/.ccache}"
    export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-5G}"
  else
    cmd+=(CC=clang CXX=clang++)
  fi
  cmd+=("$@")
  LOCALVERSION= "${cmd[@]}"
}
