#!/usr/bin/env bash
# Verify Image, pack in-tree AnyKernel, write build-info.json. Fail closed.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
# shellcheck source=version.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/version.sh"

require_kernel_tree
need_cmd zip
need_cmd python3
ensure_work_dir
compute_kernel_release

if [[ -f "${REFS_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${REFS_FILE}"
  set +a
fi

BUILD_TYPE="${BUILD_TYPE:-manual}"
IMAGE_GZ="${OUT_DIR}/arch/arm64/boot/Image.gz"

if [[ ! -f "${IMAGE_GZ}" ]]; then
  err "Kernel Image.gz not found under ${OUT_DIR}/arch/arm64/boot"
  ls -la "${OUT_DIR}/arch/arm64/boot" || true
  exit 1
fi

AK_SRC="${ROOT}/anykernel"
[[ -d "${AK_SRC}" ]] || { err "missing in-tree anykernel/"; exit 1; }

STAGING="${WORK_DIR}/anykernel-pack"
rm -rf "${STAGING}"
cp -a "${AK_SRC}" "${STAGING}"
rm -f "${STAGING}/Image"
cp -f "${IMAGE_GZ}" "${STAGING}/Image.gz"

if [[ -f "${STAGING}/anykernel.sh" ]]; then
  sed -i "s/^kernel.string=.*/kernel.string=${KERNEL_RELEASE} for ${DEVICE}/" \
    "${STAGING}/anykernel.sh" || true
fi

KERNEL_SRC_COMMIT="$(git -C "${ROOT}" rev-parse HEAD)"
ZIP_STAMP="$(TZ=Asia/Hong_Kong date +%y%m%d%H)"
ZIP_NAME="${DEVICE}-${KERNEL_VERSION}-${ZIP_STAMP}-KowSU-SUSFS.zip"
ZIP_PATH="${WORK_DIR}/${ZIP_NAME}"

(
  cd "${STAGING}"
  zip -r9 "${ZIP_PATH}" . -x '*.git*' -x '*placeholder'
)

python3 - "${ZIP_PATH}" <<'PY'
import sys, zipfile
path = sys.argv[1]
with zipfile.ZipFile(path) as zf:
    bad = zf.testzip()
    names = set(zf.namelist())
if bad:
    raise SystemExit(f"corrupt zip entry: {bad}")
if "Image.gz" not in names:
    raise SystemExit(f"AnyKernel zip missing Image.gz: {sorted(names)[:20]}")
print("zip ok", path)
PY

python3 - "${BUILD_INFO}" <<PY
import json, os, pathlib
path = pathlib.Path("${BUILD_INFO}")
data = {
    "device": "${DEVICE}",
    "kernel": "${KERNEL_VERSION}",
    "kernel_release": "${KERNEL_RELEASE}",
    "android_release": "${ANDROID_RELEASE}",
    "kmi_generation": "${KMI_GENERATION}",
    "revcount": os.environ.get("KERNEL_REVCOUNT", ""),
    "shortsha": os.environ.get("KERNEL_SHORTSHA", ""),
    "ab": os.environ.get("KERNEL_AB", ""),
    "kernel_source_commit": "${KERNEL_SRC_COMMIT}",
    "kernelsu_kow": os.environ.get("CHOSEN_KSU_REF", os.environ.get("KSU_REF", "")),
    "susfs": os.environ.get("CHOSEN_SUSFS_REF", os.environ.get("SUSFS_REF", "")),
    "pair_label": "${CHOSEN_PAIR_LABEL:-}",
    "build_type": "${BUILD_TYPE}",
    "kernel_build_timestamp": os.environ.get("KBUILD_BUILD_TIMESTAMP", ""),
    "workflow_run_id": os.environ.get("GITHUB_RUN_ID", ""),
    "zip_name": "${ZIP_NAME}",
}
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print(path.read_text(encoding="utf-8"))
PY

log "Packed ${ZIP_PATH}"
