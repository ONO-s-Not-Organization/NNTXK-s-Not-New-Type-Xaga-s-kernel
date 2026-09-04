#!/usr/bin/env bash
# Create a unique GitHub pre-release only after a verified successful pack.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_cmd gh
need_cmd python3
ensure_work_dir

[[ -f "${BUILD_INFO}" ]] || { err "missing ${BUILD_INFO}; refusing to release"; exit 1; }

BUILD_TYPE="${BUILD_TYPE:-manual}"
ZIP_PATH="${1:-}"
if [[ -z "${ZIP_PATH}" || ! -f "${ZIP_PATH}" ]]; then
  err "usage: make-release.sh <anykernel.zip>"
  exit 1
fi

KERNEL_RELEASE="$(python3 -c 'import json,pathlib,sys; print(json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")).get("kernel_release",""))' "${BUILD_INFO}")"

export TZ=Asia/Hong_Kong
PREFIX="$([[ "${BUILD_TYPE}" == "auto" ]] && echo auto || echo manual)"
STAMP="$(date +%Y%m%d)"
NEXT="$(
  python3 - "${PREFIX}" "${STAMP}" <<'PY'
import subprocess, sys
prefix, stamp = sys.argv[1], sys.argv[2]
wanted = f"{prefix}-{stamp}-"
out = subprocess.check_output(
    ["gh", "release", "list", "--limit", "100", "--json", "tagName", "--jq", ".[].tagName"],
    text=True,
)
n = 0
for tag in out.splitlines():
    tag = tag.strip()
    if tag.startswith(wanted):
        try:
            n = max(n, int(tag[len(wanted):]))
        except ValueError:
            pass
print(f"{wanted}{n+1:02d}")
PY
)"

TITLE_KIND="$([[ "${BUILD_TYPE}" == "auto" ]] && echo "Auto Build" || echo "Manual Build")"
TITLE="${TITLE_KIND}: ${DEVICE} ${KERNEL_RELEASE}"

BODY="$(python3 - "${BUILD_INFO}" "${NEXT}" "${BUILD_TYPE}" <<'PY'
import json, pathlib, sys
info = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
tag, build_type = sys.argv[2], sys.argv[3]
kind = "Automatic" if build_type == "auto" else "Manual"
pair = info.get("pair_label") or ""
pair_line = f"\nPair:\n{pair}\n" if pair else ""
print(f"""Device:
{info.get("device")}

Kernel:
{info.get("kernel")}

KernelRelease:
{info.get("kernel_release")}

Kernel source commit:
{info.get("kernel_source_commit")}

KernelSU / KOW:
{info.get("kernelsu_kow")}

SUSFS:
{info.get("susfs")}
{pair_line}
Build type:
{kind}

Verification:
Untested on device (pre-release)

Kernel build timestamp:
{info.get("kernel_build_timestamp")}

Build workflow run ID:
{info.get("workflow_run_id")}

Release tag:
{tag}
""")
PY
)"

gh release create "${NEXT}" \
  "${ZIP_PATH}" \
  "${BUILD_INFO}" \
  --prerelease \
  --title "${TITLE}" \
  --notes "${BODY}"

log "Created pre-release ${NEXT}"
