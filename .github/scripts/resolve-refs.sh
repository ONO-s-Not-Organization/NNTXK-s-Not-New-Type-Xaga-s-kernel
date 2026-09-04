#!/usr/bin/env bash
# Resolve KSU_REF / SUSFS_REF.
# latest KOW = newest commit that touches kernel/ (not manager APK).
# latest SUSFS = newest commit on gki-android12-5.10.
# Also resolve one aligned fallback pair for latest-only builds.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_cmd python3
ensure_work_dir

KSU_REF_IN="${KSU_REF:-latest}"
SUSFS_REF_IN="${SUSFS_REF:-latest}"

python3 - "${KSU_REF_IN}" "${SUSFS_REF_IN}" "${KSU_REPO}" "${SUSFS_BRANCH}" "${REFS_FILE}" <<'PY'
import json, os, ssl, sys, urllib.request

ksu_in, susfs_in, ksu_repo, susfs_branch, refs_file = sys.argv[1:6]
token = os.environ.get("GITHUB_TOKEN", "")
CTX = ssl.create_default_context(cafile="/etc/ssl/certs/ca-certificates.crt")

def get(url):
    req = urllib.request.Request(url)
    if token and "api.github.com" in url:
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("Accept", "application/vnd.github+json")
    with urllib.request.urlopen(req, timeout=60, context=CTX) as resp:
        return json.load(resp)

def latest_ksu_kernel_commit():
    data = get(f"https://api.github.com/repos/{ksu_repo}/commits?path=kernel&per_page=1")
    if not data:
        raise SystemExit("no KOW kernel/ commits found")
    return data[0]["sha"]

def latest_ksu_clean_tag():
    data = get(f"https://api.github.com/repos/{ksu_repo}/tags?per_page=20")
    if not data:
        raise SystemExit("no KOW tags found")
    for item in data:
        name = item["name"]
        if name.count("-") == 0:
            return name, item["commit"]["sha"]
    return data[0]["name"], data[0]["commit"]["sha"]

def resolve_ksu_sha(ref):
    return get(f"https://api.github.com/repos/{ksu_repo}/commits/{ref}")["sha"]

def latest_susfs_commit():
    proj = "simonpunk%2Fsusfs4ksu"
    data = get(
        f"https://gitlab.com/api/v4/projects/{proj}/repository/commits"
        f"?ref_name={susfs_branch}&per_page=1"
    )
    return data[0]["id"]

def latest_susfs_bump():
    proj = "simonpunk%2Fsusfs4ksu"
    data = get(
        f"https://gitlab.com/api/v4/projects/{proj}/repository/commits"
        f"?ref_name={susfs_branch}&per_page=50"
    )
    for item in data:
        if item.get("title", "").startswith("Bump version"):
            return item["id"], item["title"]
    return data[0]["id"], data[0].get("title", "")

def resolve_susfs_sha(ref):
    proj = "simonpunk%2Fsusfs4ksu"
    return get(
        f"https://gitlab.com/api/v4/projects/{proj}/repository/commits/{ref}"
    )["id"]

ksu_kernel_sha = latest_ksu_kernel_commit()
ksu_tag, ksu_tag_sha = latest_ksu_clean_tag()
susfs_head = latest_susfs_commit()
susfs_bump_sha, susfs_bump_title = latest_susfs_bump()

if ksu_in in ("", "latest"):
    ksu_ref = ksu_kernel_sha
    ksu_kind = "kernel-path-latest"
else:
    ksu_ref = resolve_ksu_sha(ksu_in)
    ksu_kind = "explicit"

if susfs_in in ("", "latest"):
    susfs_ref = susfs_head
    susfs_kind = "branch-head"
else:
    susfs_ref = resolve_susfs_sha(susfs_in)
    susfs_kind = "explicit"

lines = [
    f"KSU_REF={ksu_ref}",
    f"KSU_REF_IN={ksu_in}",
    f"KSU_KIND={ksu_kind}",
    f"KSU_KERNEL_LATEST={ksu_kernel_sha}",
    f"KSU_FALLBACK_TAG={ksu_tag}",
    f"KSU_FALLBACK_TAG_SHA={ksu_tag_sha}",
    f"SUSFS_REF={susfs_ref}",
    f"SUSFS_REF_IN={susfs_in}",
    f"SUSFS_KIND={susfs_kind}",
    f"SUSFS_HEAD={susfs_head}",
    f"SUSFS_FALLBACK_BUMP={susfs_bump_sha}",
    f"SUSFS_FALLBACK_BUMP_TITLE={susfs_bump_title}",
]
os.makedirs(os.path.dirname(refs_file) or ".", exist_ok=True)
with open(refs_file, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
print("\n".join(lines))
PY

# shellcheck disable=SC1090
source "${REFS_FILE}"
log "Resolved KSU_REF=${KSU_REF} SUSFS_REF=${SUSFS_REF}"
