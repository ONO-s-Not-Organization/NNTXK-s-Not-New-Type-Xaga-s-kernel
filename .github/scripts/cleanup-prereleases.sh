#!/usr/bin/env bash
# Delete pre-releases older than 30 days in Asia/Hong_Kong. Keep official releases.
set -euo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

need_cmd gh
need_cmd python3

export TZ=Asia/Hong_Kong

python3 <<'PY'
import json, subprocess, sys
from datetime import datetime, timedelta, timezone

try:
    from zoneinfo import ZoneInfo
    hk = ZoneInfo("Asia/Hong_Kong")
except Exception:
    hk = timezone(timedelta(hours=8))

now = datetime.now(tz=hk)
cutoff = now - timedelta(days=30)

raw = subprocess.check_output(
    ["gh", "release", "list", "--limit", "200", "--json", "tagName,isPrerelease,createdAt"],
    text=True,
)
releases = json.loads(raw)
deleted = []
for rel in releases:
    if not rel.get("isPrerelease"):
        continue
    created = datetime.fromisoformat(rel["createdAt"].replace("Z", "+00:00")).astimezone(hk)
    if created >= cutoff:
        continue
    tag = rel["tagName"]
    print(f"deleting pre-release {tag} created {created.isoformat()}", flush=True)
    subprocess.check_call(["gh", "release", "delete", tag, "--yes", "--cleanup-tag"])
    deleted.append(tag)
print(f"deleted {len(deleted)} pre-release(s)")
PY
