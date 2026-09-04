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
TITLE="${TITLE_KIND}: ${DEVICE} ${KERNEL_VERSION} KowSU-SUSFS"

BODY="$(
  python3 - "${BUILD_INFO}" "${NEXT}" "${BUILD_TYPE}" <<'PY'
import json, os, pathlib, sys

def strip_git(url):
    url = (url or "").rstrip("/")
    if url.endswith(".git"):
        url = url[:-4]
    return url

info = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
tag, build_type = sys.argv[2], sys.argv[3]
kind = "Automatic" if build_type == "auto" else "Manual"
pair = info.get("pair_label") or ""
pair_block = f"\nPair:\n{pair}\n" if pair else ""

server = os.environ.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/")
repo = os.environ.get("GITHUB_REPOSITORY", "")
kernel_repo = f"{server}/{repo}" if repo else ""
ksu_repo = strip_git(os.environ.get("KSU_CLONE_URL", "https://github.com/KOWX712/KernelSU.git"))
susfs_repo = strip_git(os.environ.get("SUSFS_CLONE_URL", "https://gitlab.com/simonpunk/susfs4ksu.git"))
susfs_branch = os.environ.get("SUSFS_BRANCH", "gki-android12-5.10")
user = os.environ.get("KBUILD_BUILD_USER", "build-user")
host = os.environ.get("KBUILD_BUILD_HOST", "build-host")

ksha = info.get("kernel_source_commit") or ""
kow = info.get("kernelsu_kow") or ""
sus = info.get("susfs") or ""
run = str(info.get("workflow_run_id") or "")

kernel_commit = f"{kernel_repo}/commit/{ksha}" if kernel_repo and ksha else ksha
kow_commit = f"{ksu_repo}/commit/{kow}" if kow else ""
sus_commit = f"{susfs_repo}/-/commit/{sus}" if sus else ""
actions = f"{kernel_repo}/actions/runs/{run}" if kernel_repo and run else run

print(f"""Device:
{info.get("device")}

Kernel:
{info.get("kernel")}

Kernel repository:
{kernel_repo}

Kernel source commit:
{kernel_commit}

KernelRelease:
{info.get("kernel_release")}

KernelSU / KOW:
{ksu_repo}
{kow_commit}
(only kernel/ tree)

SUSFS:
{susfs_repo}
branch: {susfs_branch}
{sus_commit}
{pair_block}
Build type:
{kind}

Verification:
Untested on device (pre-release)

Kernel build timestamp:
{info.get("kernel_build_timestamp")}

Build user@host:
{user}@{host}

Build workflow run ID:
{run}

Actions run:
{actions}

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
