#!/usr/bin/env bash
# Compare KOW kernel/, SUSFS, and this repo HEAD against the last successful Release.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_cmd python3
ensure_work_dir

KSU_REF=latest SUSFS_REF=latest "${SCRIPT_DIR}/resolve-refs.sh"
# shellcheck disable=SC1090
source "${REFS_FILE}"

python3 - "${REFS_FILE}" "${WORK_DIR}/update-decision.env" <<'PY'
import json, os, pathlib, ssl, sys, urllib.request

refs_path, out_path = sys.argv[1:3]
refs = {}
for line in pathlib.Path(refs_path).read_text(encoding="utf-8").splitlines():
    if "=" in line:
        k, v = line.split("=", 1)
        refs[k] = v

latest_ksu = refs.get("KSU_KERNEL_LATEST") or refs.get("KSU_REF")
latest_susfs = refs.get("SUSFS_HEAD") or refs.get("SUSFS_REF")
latest_kernel = os.environ.get("GITHUB_SHA", "")

prev_ksu = ""
prev_susfs = ""
prev_kernel = ""
source = "none"

token = os.environ.get("GITHUB_TOKEN", "")
repo = os.environ.get("GITHUB_REPOSITORY", "")
CTX = ssl.create_default_context(cafile="/etc/ssl/certs/ca-certificates.crt")
if repo and token:
    try:
        req = urllib.request.Request(
            f"https://api.github.com/repos/{repo}/releases?per_page=20",
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
            },
        )
        with urllib.request.urlopen(req, timeout=60, context=CTX) as resp:
            releases = json.loads(resp.read().decode())
        for rel in releases:
            tag = rel.get("tag_name", "")
            if not tag.startswith("auto-") and not tag.startswith("manual-"):
                continue
            for asset in rel.get("assets", []):
                if asset.get("name") == "build-info.json":
                    req2 = urllib.request.Request(
                        asset["url"],
                        headers={
                            "Authorization": f"Bearer {token}",
                            "Accept": "application/octet-stream",
                        },
                    )
                    with urllib.request.urlopen(req2, timeout=60, context=CTX) as resp2:
                        info = json.loads(resp2.read().decode())
                    prev_ksu = info.get("kernelsu_kow") or ""
                    prev_susfs = info.get("susfs") or ""
                    prev_kernel = info.get("kernel_source_commit") or ""
                    source = f"release:{tag}"
                    raise StopIteration
    except StopIteration:
        pass
    except Exception as exc:
        print(f"[!] could not read previous release: {exc}", file=sys.stderr)

should = "false"
reasons = []
if not prev_ksu or not prev_susfs or not prev_kernel:
    should = "true"
    reasons.append("no previous successful build record")
if prev_ksu and latest_ksu and prev_ksu != latest_ksu:
    should = "true"
    reasons.append(f"KOW kernel/ {prev_ksu} -> {latest_ksu}")
if prev_susfs and latest_susfs and prev_susfs != latest_susfs:
    should = "true"
    reasons.append(f"SUSFS {prev_susfs} -> {latest_susfs}")
if prev_kernel and latest_kernel and prev_kernel != latest_kernel:
    should = "true"
    reasons.append(f"Kernel HEAD {prev_kernel} -> {latest_kernel}")
if should == "false":
    reasons.append("Kernel HEAD, KOW kernel/, and SUSFS unchanged")

pathlib.Path(out_path).write_text(
    "\n".join(
        [
            f"SHOULD_BUILD={should}",
            f"PREV_KSU={prev_ksu}",
            f"PREV_SUSFS={prev_susfs}",
            f"PREV_KERNEL={prev_kernel}",
            f"LATEST_KSU={latest_ksu}",
            f"LATEST_SUSFS={latest_susfs}",
            f"LATEST_KERNEL={latest_kernel}",
            f"COMPARE_SOURCE={source}",
            f"REASON={' | '.join(reasons)}",
        ]
    )
    + "\n",
    encoding="utf-8",
)
print(pathlib.Path(out_path).read_text(encoding="utf-8"))
PY

# shellcheck disable=SC1090
source "${WORK_DIR}/update-decision.env"
write_github_output should_build "${SHOULD_BUILD}"
write_github_output latest_ksu "${LATEST_KSU}"
write_github_output latest_susfs "${LATEST_SUSFS}"
write_github_output reason "${REASON}"
log "should_build=${SHOULD_BUILD} (${REASON})"
