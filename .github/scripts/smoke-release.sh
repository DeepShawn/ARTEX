#!/usr/bin/env bash
# Exercise the packaged launcher, embedded UI and API against a real PostgreSQL.
set -euo pipefail

archive="${1:?Usage: smoke-release.sh ARCHIVE VERSION}"
version="${2:?Usage: smoke-release.sh ARCHIVE VERSION}"
version="${version#v}"
: "${APAGENT_PG_DSN:?Set APAGENT_PG_DSN to an isolated smoke-test database}"
port="${APAGENT_SMOKE_PORT:-18787}"
smoke_dir="$(mktemp -d)"
launcher_pid=""
cleanup() {
  result=$?
  trap - EXIT
  if [ -n "$launcher_pid" ]; then
    kill -TERM "$launcher_pid" 2>/dev/null || true
    wait "$launcher_pid" 2>/dev/null || true
  fi
  if [ "$result" -ne 0 ] && [ -f "$smoke_dir/server.log" ]; then
    cat "$smoke_dir/server.log" >&2
  fi
  rm -rf "$smoke_dir"
  exit "$result"
}
trap cleanup EXIT

unzip -tq "$archive"
unzip -q "$archive" -d "$smoke_dir"
package_dir="$smoke_dir/apagent-${version}-linux-amd64"
for required in apagent start.sh config.example.json README.md LICENSE NOTICE CHANGELOG.md; do
  test -f "$package_dir/$required"
done
test -d "$package_dir/skills"
"$package_dir/apagent" -h
APAGENT_CONFIG="$smoke_dir/config.json" APAGENT_SKILL_DIR="$package_dir/skills" \
  "$package_dir/start.sh" -addr "127.0.0.1:$port" -proxy "" \
  -data "$smoke_dir/data" >"$smoke_dir/server.log" 2>&1 &
launcher_pid=$!

ready=0
for attempt in $(seq 1 60); do
  if curl --silent --fail "http://127.0.0.1:$port/api/health" >"$smoke_dir/health.json"; then
    ready=1
    break
  fi
  kill -0 "$launcher_pid"
  sleep 1
done
test "$ready" = 1
python3 - "$smoke_dir/health.json" "$version" <<'PY'
import json
import sys
with open(sys.argv[1]) as response:
    health = json.load(response)
assert health.get("ok") is True, health
assert health.get("service") == "apagent", health
assert health.get("version") == sys.argv[2], health
PY

curl --silent --show-error --fail "http://127.0.0.1:$port/api/auth/status" >"$smoke_dir/auth.json"
python3 - "$smoke_dir/auth.json" <<'PY'
import json
import sys
with open(sys.argv[1]) as response:
    status = json.load(response)
assert isinstance(status.get("initialized"), bool), status
PY

curl --silent --show-error --fail "http://127.0.0.1:$port/setup/" >"$smoke_dir/setup.html"
asset="$(python3 - "$smoke_dir/setup.html" <<'PY'
import re
import sys
with open(sys.argv[1]) as response:
    html = response.read()
assert "<html" in html.lower(), "Embedded setup page is missing"
scripts = re.findall(r'<script[^>]+src="([^"]+)"', html)
assets = [src for src in scripts if src.startswith("/_next/") and ".js" in src]
assert assets, "Production JavaScript assets are missing or have a Pages base path"
print(assets[0])
PY
)"
curl --silent --show-error --fail "http://127.0.0.1:$port$asset" >"$smoke_dir/asset.js"
test -s "$smoke_dir/asset.js"
if head -c 100 "$smoke_dir/asset.js" | rg -qi '<!doctype|<html'; then
  echo "Embedded JavaScript request returned the HTML fallback" >&2
  exit 1
fi
echo "Packaged release $version passed launcher, API, setup page and JavaScript smoke checks."
