#!/data/data/com.termux/files/usr/bin/bash
# Install a checked Android arm64 runtime into Termux. Existing user data is retained.
set -euo pipefail
umask 077
die() { printf '[ARTEX] %s\n' "$*" >&2; exit 1; }
info() { printf '[ARTEX] %s\n' "$*"; }
usage() {
  cat <<'EOF'
Usage: bash bootstrap.sh --runtime-url URL --sha256 HEX [options]
       bash bootstrap.sh --runtime-file FILE [--sha256 HEX] [options]
Options:
  --abi ABI          Runtime architecture: arm64-v8a (default), x86_64 (emulator).
  --port PORT        Local UI/API port (default: 8787).
  --proxy-port PORT  Local recording proxy (default: 8788; 0 disables it).
  --pg-port PORT     This installation PostgreSQL port (default: 15432).
  --home DIR         Installation directory (default: $HOME/.local/share/artex).
  --ready-url URL    Optional token-protected loopback acknowledgement for the APK.
  --foreground       Keep a Termux RUN_COMMAND task active after installation.
All services bind to 127.0.0.1. Reinstalling retains PostgreSQL, settings, skills and JWT.
EOF
}
runtime_url='' runtime_file='' expected_sha='' requested_port='' requested_proxy='' requested_pg='' ready_url='' foreground=0 runtime_abi=arm64-v8a
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --runtime-url|--runtime-file|--sha256|--port|--proxy-port|--pg-port|--home|--ready-url|--abi)
      [[ "$#" -ge 2 ]] || die "Missing value for $1"
      case "$1" in
        --runtime-url) runtime_url="$2" ;;
        --runtime-file) runtime_file="$2" ;;
        --sha256) expected_sha="${2,,}" ;;
        --port) requested_port="$2" ;;
        --proxy-port) requested_proxy="$2" ;;
        --pg-port) requested_pg="$2" ;;
        --home) ARTEX_HOME="$2" ;;
        --ready-url) ready_url="$2" ;;
        --abi) runtime_abi="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --foreground) foreground=1; shift ;;
    *) die "Unknown argument: $1" ;;
  esac
done
[[ -n "$runtime_url" && -z "$runtime_file" || -z "$runtime_url" && -n "$runtime_file" ]] \
  || die 'Select exactly one of --runtime-url and --runtime-file.'
[[ -z "$expected_sha" || "$expected_sha" =~ ^[a-f0-9]{64}$ ]] || die 'SHA256 must contain 64 hex characters.'
[[ -z "$runtime_url" || -n "$expected_sha" ]] || die 'Downloaded runtimes require --sha256.'
command -v pkg >/dev/null || die 'Run this script inside Termux (official F-Droid or GitHub distribution).'
[[ "$(id -u)" != 0 ]] || die 'Run as the regular Termux user, without su/root.'
case "$runtime_abi:$(uname -m)" in
  arm64-v8a:aarch64|arm64-v8a:arm64|x86_64:x86_64) ;;
  *) die "This runtime requires an Android $runtime_abi device." ;;
esac

ARTEX_HOME="${ARTEX_HOME:-$HOME/.local/share/artex}"
mkdir -p -- "$ARTEX_HOME/run" "$ARTEX_HOME/config"
ARTEX_HOME="$(cd -- "$ARTEX_HOME" && pwd -P)"
export ARTEX_HOME
info 'Installing Termux PostgreSQL, Python, Node.js and command-line tools...'
# The APK feeds this script through bash -s; package managers must not consume
# the remaining script from that same stdin stream. apt's -y does not answer
# dpkg conffile questions (for example Termux's pre-existing openssl.cnf).
# Retain the user's configuration and recover a previous interrupted setup.
command -v dpkg >/dev/null || die 'This installer requires the official apt/dpkg-based Termux distribution.'
export DEBIAN_FRONTEND=noninteractive UCF_FORCE_CONFFOLD=1
package_options=(-y -o Dpkg::Options::=--force-confold)
pkg update -y < /dev/null \
  || die 'Package index update failed. Open Termux, check its network/repository, then retry.'
if ! dpkg --force-confold --configure -a < /dev/null; then
  info 'Repairing interrupted Termux package dependencies...'
  pkg install "${package_options[@]}" --fix-broken < /dev/null \
    || die 'Package recovery failed. In Termux run: dpkg --configure -a; apt --fix-broken install. Then retry ARTEX initialization.'
fi
pkg install "${package_options[@]}" postgresql python nmap ripgrep curl tar coreutils openssl openssl-tool ca-certificates jq util-linux nodejs-lts < /dev/null \
  || die 'Package installation failed. In Termux run: dpkg --configure -a; apt --fix-broken install. Keep existing configuration files when asked, then retry ARTEX initialization.'
exec 8> "$ARTEX_HOME/run/install.lock"
flock -w 30 8 || die 'Another ARTEX installation is in progress.'
stage="$(mktemp -d "$ARTEX_HOME/run/install.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
archive="$stage/runtime.tar.gz"

if [[ -n "$ready_url" ]]; then
  python - "$ready_url" <<'PY'
import sys, urllib.parse
u = urllib.parse.urlsplit(sys.argv[1])
ok = u.scheme == 'http' and u.hostname in ('127.0.0.1', 'localhost', '::1')
sys.exit(0 if ok and not u.username and not u.password else 1)
PY
fi

if [[ -n "$runtime_url" ]]; then
  python - "$runtime_url" <<'PY'
import sys, urllib.parse
u = urllib.parse.urlsplit(sys.argv[1])
ok = u.scheme == 'https' or (u.scheme == 'http' and u.hostname in ('127.0.0.1', 'localhost', '::1'))
sys.exit(0 if ok and not u.username and not u.password else 1)
PY
  info 'Downloading the local runtime (URL token is not logged)...'
  curl --noproxy '127.0.0.1,localhost,::1' --fail --show-error --silent --location --retry 2 --proto '=http,https' --proto-redir '=https' \
    --output "$archive" "$runtime_url"
else
  [[ -f "$runtime_file" ]] || die 'Runtime file does not exist.'
  cp -- "$runtime_file" "$archive"
fi
if [[ -n "$expected_sha" ]]; then
  printf '%s  %s\n' "$expected_sha" "$archive" | sha256sum --check --status \
    || die 'Runtime checksum mismatch; the installed runtime was not changed.'
fi

# Reject links, devices and paths escaping the staging directory before extraction.
python - "$archive" "$stage/unpacked" <<'PY'
import pathlib, sys, tarfile
dest = pathlib.Path(sys.argv[2])
dest.mkdir()
with tarfile.open(sys.argv[1], 'r:gz') as t:
    members = t.getmembers()
    for item in members:
        p = pathlib.PurePosixPath(item.name)
        if p.is_absolute() or '..' in p.parts or not (item.isfile() or item.isdir()):
            raise SystemExit('Unsafe runtime archive entry; existing runtime unchanged.')
    t.extractall(dest, members=members, filter='data')
PY
payload="$stage/unpacked"
if [[ ! -f "$payload/apagent" ]]; then
  shopt -s nullglob dotglob
  entries=("$payload"/*)
  [[ "${#entries[@]}" == 1 && -d "${entries[0]}" ]] || die 'Runtime archive must contain apagent at its root.'
  payload="${entries[0]}"
fi
for item in apagent termux/common.sh termux/start.sh termux/stop.sh termux/status.sh; do
  [[ -f "$payload/$item" ]] || die "Runtime archive is missing $item"
done
[[ -d "$payload/skills" ]] || die 'Runtime archive is missing skills/.'
chmod 700 "$payload/apagent"
if ! "$payload/apagent" -h > "$stage/runtime-check.log" 2>&1; then
  cat "$stage/runtime-check.log" >&2
  die 'The runtime cannot execute on this device; current installation was not changed.'
fi

source "$payload/termux/common.sh"
artex_init
[[ -z "$requested_port" ]] || ARTEX_PORT="$requested_port"
[[ -z "$requested_proxy" ]] || ARTEX_PROXY_PORT="$requested_proxy"
[[ -z "$requested_pg" ]] || ARTEX_PG_PORT="$requested_pg"
artex_validate_ports
artex_lock
if [[ -f "$ARTEX_PGDATA/PG_VERSION" && ! -f "$ARTEX_PGDATA/.artex-owned" ]]; then
  die 'An unrecognized database directory already exists; it was not adopted or modified.'
fi
artex_check_postgres_version
if old_pid="$(artex_pg_pid)"; then
  old_pg_port="$(sed -n '4p' "$ARTEX_PGDATA/postmaster.pid")"
  [[ "$old_pg_port" == "$ARTEX_PG_PORT" ]] || die 'Stop this installation before changing its PostgreSQL port.'
fi
if [[ ! -s "$ARTEX_HOME/config/postgres.password" ]]; then
  [[ ! -f "$ARTEX_PGDATA/PG_VERSION" ]] || die 'Existing database credential file is missing or empty; it was not reset.'
  # openssl is the library package; its CLI is supplied by openssl-tool. Older
  # installs could leave an empty password when that command was unavailable.
  # Generate and check in staging so failure never truncates a saved credential.
  openssl rand -hex 24 > "$stage/new-postgres.password" \
    || die 'Database credential generation failed; existing credentials were not changed.'
  IFS= read -r database_password < "$stage/new-postgres.password"
  [[ "$database_password" =~ ^[a-f0-9]{48}$ ]] || die 'Database credential generator returned an invalid value.'
  chmod 600 "$stage/new-postgres.password"
  mv -f -- "$stage/new-postgres.password" "$ARTEX_HOME/config/postgres.password"
fi
database_password=''
IFS= read -r database_password < "$ARTEX_HOME/config/postgres.password" || [[ -n "$database_password" ]]
[[ "$database_password" =~ ^[a-f0-9]{48}$ ]] || die 'Invalid installation database credential file; existing credentials and database were preserved.'
unset database_password
artex_stop_backend
printf 'ARTEX_PORT=%s\nARTEX_PROXY_PORT=%s\nARTEX_PG_PORT=%s\n' \
  "$ARTEX_PORT" "$ARTEX_PROXY_PORT" "$ARTEX_PG_PORT" > "$ARTEX_HOME/config/ports.env"
if [[ ! -f "$ARTEX_PGDATA/PG_VERSION" ]]; then
  [[ ! -e "$ARTEX_PGDATA" ]] || die 'PostgreSQL path already exists without a recognized cluster; refusing to overwrite it.'
  info 'Initializing this installation PostgreSQL cluster...'
  if ! initdb -D "$stage/new-postgres" -U artex --encoding=UTF8 --locale=C \
    --auth-local=trust --auth-host=scram-sha-256 --pwfile="$ARTEX_HOME/config/postgres.password" \
    < /dev/null > "$ARTEX_LOGS/initdb.log" 2>&1 8>&- 9>&-; then
    printf '[ARTEX] PostgreSQL initialization log (last 80 lines):\n' >&2
    tail -n 80 "$ARTEX_LOGS/initdb.log" >&2
    die "PostgreSQL initialization failed; full log: $ARTEX_LOGS/initdb.log"
  fi
  printf '%s\n' 'ARTEX managed cluster' > "$stage/new-postgres/.artex-owned"
  mv -- "$stage/new-postgres" "$ARTEX_PGDATA"
fi
if [[ ! -f "$ARTEX_HOME/config/config.json" ]]; then
  python - "$ARTEX_HOME" "$ARTEX_PG_PORT" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
password = (root / 'config/postgres.password').read_text().strip()
config = {'database': {'host': '127.0.0.1', 'port': int(sys.argv[2]), 'user': 'artex',
                       'password': password, 'dbname': 'artex', 'sslmode': 'disable'},
          'skill_dir': str(root / 'skills')}
(root / 'config/config.json').write_text(json.dumps(config, indent=2) + '\n')
PY
fi

mkdir -p -- "$ARTEX_HOME/bin" "$ARTEX_RUNTIME"
cp -- "$payload/apagent" "$ARTEX_RUNTIME/apagent.next"
chmod 700 "$ARTEX_RUNTIME/apagent.next"
if [[ -f "$ARTEX_RUNTIME/apagent" ]]; then
  cp -p -- "$ARTEX_RUNTIME/apagent" "$ARTEX_RUNTIME/apagent.previous"
fi
mv -f -- "$ARTEX_RUNTIME/apagent.next" "$ARTEX_RUNTIME/apagent"
for item in common start stop status; do
  cp -- "$payload/termux/$item.sh" "$ARTEX_HOME/bin/$item.sh"
  chmod 700 "$ARTEX_HOME/bin/$item.sh"
done
mkdir -p -- "$ARTEX_HOME/docs"
for item in LICENSE NOTICE CHANGELOG.md ANDROID-README.md SOURCE.txt SYSTEM_PROMPT_ENTRYPOINTS.md; do
  if [[ -f "$payload/$item" ]]; then
    cp -- "$payload/$item" "$ARTEX_HOME/docs/$item"
  fi
done
# Seed defaults without replacing user-edited skills on a repeat installation.
python - "$payload/skills" "$ARTEX_HOME/skills" <<'PY'
import os, pathlib, shutil, sys
src, dst = map(pathlib.Path, sys.argv[1:])
for base, dirs, files in os.walk(src):
    target = dst / pathlib.Path(base).relative_to(src)
    target.mkdir(parents=True, exist_ok=True)
    for name in files:
        if not (target / name).exists():
            shutil.copy2(pathlib.Path(base) / name, target / name)
PY
artex_database_env
artex_ensure_postgres
# Release the control lock before calling the installed manager (which takes it itself).
flock -u 9
exec 9>&-
"$ARTEX_HOME/bin/start.sh" 8>&-
if [[ -n "$ready_url" ]]; then
  # Acknowledge this completed installation, rather than an unrelated old backend.
  curl --noproxy '*' --fail --silent --show-error --max-time 10 --retry 2 \
    "$ready_url" > /dev/null || die 'The local backend is ready, but the APK acknowledgement failed.'
fi
info 'Installation complete. PostgreSQL and the ARTEX backend both run on this device.'
info 'Playwright/Chromium is optional and is not guaranteed to run on Android; it was not installed.'
info 'Android may stop background processes; keep Termux running and allow its battery exemption.'
if [[ "$foreground" == 1 ]]; then
  # Remove temporary downloads and release the installer lock before the long session.
  rm -rf -- "$stage"
  trap - EXIT
  flock -u 8
  exec 8>&-
  exec "$ARTEX_HOME/bin/start.sh" --foreground
fi
