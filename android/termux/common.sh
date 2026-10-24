#!/data/data/com.termux/files/usr/bin/bash
# Shared helpers for this installation only. No process is identified by name alone.

artex_die() { printf '[ARTEX] %s\n' "$*" >&2; exit 1; }
artex_info() { printf '[ARTEX] %s\n' "$*"; }

artex_init() {
  umask 077
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  if [[ -z "${ARTEX_HOME:-}" ]]; then
    if [[ -d "$script_dir/../runtime" ]]; then
      ARTEX_HOME="$(cd -- "$script_dir/.." && pwd -P)"
    else
      ARTEX_HOME="$HOME/.local/share/artex"
    fi
  fi
  mkdir -p -- "$ARTEX_HOME"
  ARTEX_HOME="$(cd -- "$ARTEX_HOME" && pwd -P)"
  export ARTEX_HOME
  ARTEX_RUNTIME="$ARTEX_HOME/runtime"
  ARTEX_PGDATA="$ARTEX_HOME/postgres"
  ARTEX_RUN="$ARTEX_HOME/run"
  ARTEX_LOGS="$ARTEX_HOME/logs"
  mkdir -p -- "$ARTEX_RUN" "$ARTEX_LOGS" "$ARTEX_HOME/config" "$ARTEX_HOME/data" "$ARTEX_HOME/skills"
  ARTEX_PORT=8787
  ARTEX_PROXY_PORT=8788
  ARTEX_PG_PORT=15432
  local key value
  if [[ -f "$ARTEX_HOME/config/ports.env" ]]; then
    while IFS='=' read -r key value; do
      case "$key" in
        ARTEX_PORT|ARTEX_PROXY_PORT|ARTEX_PG_PORT)
          [[ "$value" =~ ^[0-9]+$ ]] || artex_die "Invalid port configuration: $key"
          printf -v "$key" '%s' "$value"
          ;;
      esac
    done < "$ARTEX_HOME/config/ports.env"
  fi
  artex_validate_ports
}

artex_validate_ports() {
  local name value
  for name in ARTEX_PORT ARTEX_PROXY_PORT ARTEX_PG_PORT; do
    value="${!name}"
    [[ "$value" =~ ^[0-9]{1,5}$ ]] || artex_die "Invalid port: $name"
    value="$((10#$value))"
    [[ "$value" -le 65535 && ( "$value" -gt 0 || "$name" == ARTEX_PROXY_PORT ) ]] \
      || artex_die "Port out of range: $name"
    printf -v "$name" '%s' "$value"
  done
  [[ "$ARTEX_PORT" != "$ARTEX_PG_PORT" && "$ARTEX_PORT" != "$ARTEX_PROXY_PORT" && "$ARTEX_PG_PORT" != "$ARTEX_PROXY_PORT" ]] \
    || artex_die 'Application, proxy and PostgreSQL ports must differ (proxy 0 disables capture).'
}

artex_lock() {
  command -v flock >/dev/null || artex_die 'Missing flock; run bootstrap.sh to install dependencies.'
  exec 9> "$ARTEX_RUN/control.lock"
  flock -w 30 9 || artex_die 'Another ARTEX start/stop operation is still running.'
}

artex_backend_pid() {
  local pid exe
  [[ -r "$ARTEX_RUN/apagent.pid" ]] || return 1
  read -r pid < "$ARTEX_RUN/apagent.pid"
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null || return 1
  exe="$(readlink "/proc/$pid/exe" 2>/dev/null)" || return 1
  [[ "$exe" == "$ARTEX_RUNTIME/apagent" || "$exe" == "$ARTEX_RUNTIME/apagent (deleted)" ]] || return 1
  printf '%s\n' "$pid"
}

artex_pg_pid() {
  [[ -f "$ARTEX_PGDATA/.artex-owned" && -r "$ARTEX_PGDATA/postmaster.pid" ]] || return 1
  local pid
  read -r pid < "$ARTEX_PGDATA/postmaster.pid"
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null || return 1
  # PostgreSQL must have been launched with this exact cluster directory.
  python - "$pid" "$ARTEX_PGDATA" <<'PY'
import os, pathlib, sys
try:
    args = pathlib.Path('/proc', sys.argv[1], 'cmdline').read_bytes().split(b'\0')
    i = args.index(b'-D')
    valid = os.path.realpath(os.fsdecode(args[i + 1])) == os.path.realpath(sys.argv[2])
    exe = os.path.basename(os.readlink('/proc/' + sys.argv[1] + '/exe')).removesuffix(' (deleted)')
    valid = valid and exe == 'postgres'
except (OSError, ValueError, IndexError):
    valid = False
sys.exit(0 if valid else 1)
PY
  [[ "$?" == 0 ]] || return 1
  printf '%s\n' "$pid"
}

artex_check_port_free() {
  python - "$1" <<'PY'
import socket, sys
with socket.socket() as s:
    try:
        s.bind(('127.0.0.1', int(sys.argv[1])))
    except OSError:
        print('[ARTEX] Loopback port ' + sys.argv[1] + ' is occupied by another process.', file=sys.stderr)
        sys.exit(1)
PY
}

artex_database_env() {
  [[ -s "$ARTEX_HOME/config/postgres.password" ]] || artex_die 'Missing database credentials; run bootstrap.sh.'
  local password
  read -r password < "$ARTEX_HOME/config/postgres.password"
  [[ "$password" =~ ^[a-f0-9]{48}$ ]] || artex_die 'Invalid installation database credential file.'
  # The generated password is URL-safe. Never print this value or the DSN.
  export APAGENT_PG_DSN="postgres://artex:${password}@127.0.0.1:${ARTEX_PG_PORT}/artex?sslmode=disable"
  export APAGENT_BASE_DIR="$ARTEX_HOME"
  export APAGENT_CONFIG="$ARTEX_HOME/config/config.json"
  export APAGENT_SKILL_DIR="$ARTEX_HOME/skills"
  export ARTEX_DB_PASSWORD="$password"
  # Termux ships Mozilla roots here; retain any explicit user CA selection.
  if [[ -z "${SSL_CERT_FILE:-}" && -n "${PREFIX:-}" && -f "$PREFIX/etc/tls/cert.pem" ]]; then
    export SSL_CERT_FILE="$PREFIX/etc/tls/cert.pem"
  fi
}

artex_check_postgres_version() {
  [[ -f "$ARTEX_PGDATA/PG_VERSION" ]] || return 0
  local cluster_major installed_major
  read -r cluster_major < "$ARTEX_PGDATA/PG_VERSION"
  installed_major="$(postgres --version | sed -E 's/.*PostgreSQL\) ([0-9]+).*/\1/')"
  [[ "$cluster_major" == "$installed_major" ]] \
    || artex_die "PostgreSQL package major $installed_major differs from cluster $cluster_major. Back up and migrate this cluster; it was not reset."
}

artex_ensure_postgres() {
  [[ -f "$ARTEX_PGDATA/.artex-owned" && -f "$ARTEX_PGDATA/PG_VERSION" ]] \
    || artex_die 'This directory is not an initialized ARTEX PostgreSQL cluster; run bootstrap.sh.'
  artex_check_postgres_version
  if ! artex_pg_pid >/dev/null; then
    artex_check_port_free "$ARTEX_PG_PORT" || artex_die 'PostgreSQL port conflict; existing services were left running.'
    artex_info 'Starting local PostgreSQL...'
    pg_ctl -D "$ARTEX_PGDATA" -l "$ARTEX_LOGS/postgres.log" \
      -o "-h 127.0.0.1 -p $ARTEX_PG_PORT -c unix_socket_directories='' -c max_connections=48 -c shared_buffers=32MB" \
      -w -t 60 start < /dev/null 8>&- 9>&- || artex_die "PostgreSQL failed; inspect $ARTEX_LOGS/postgres.log"
    artex_pg_pid >/dev/null || artex_die 'Could not verify ownership of the started PostgreSQL process.'
  fi
  PGPASSWORD="$ARTEX_DB_PASSWORD" psql -h 127.0.0.1 -p "$ARTEX_PG_PORT" -U artex -d postgres \
    -X -v ON_ERROR_STOP=1 -Atqc 'SELECT 1' >/dev/null \
    || artex_die 'Could not authenticate to the installation database; credentials were preserved.'
  if [[ "$(PGPASSWORD="$ARTEX_DB_PASSWORD" psql -h 127.0.0.1 -p "$ARTEX_PG_PORT" -U artex -d postgres \
    -X -v ON_ERROR_STOP=1 -Atqc "SELECT 1 FROM pg_database WHERE datname='artex'")" != 1 ]]; then
    PGPASSWORD="$ARTEX_DB_PASSWORD" createdb -h 127.0.0.1 -p "$ARTEX_PG_PORT" -U artex artex
  fi
}

artex_stop_backend() {
  local pid attempt
  if pid="$(artex_backend_pid)"; then
    artex_info 'Stopping this installation backend...'
    kill -TERM "$pid"
    for attempt in {1..30}; do
      artex_backend_pid >/dev/null || break
      sleep 1
    done
    if artex_backend_pid >/dev/null; then
      artex_die 'Backend is still shutting down. It was not force-killed; retry stop.sh later.'
    fi
  fi
  rm -f -- "$ARTEX_RUN/apagent.pid"
}

artex_hold_foreground() {
  # Keep a Termux RUN_COMMAND AppShell task alive after installation. The APK polls
  # health separately instead of waiting for this intentionally long-lived command.
  flock -u 9
  exec 9>&-
  artex_info 'Foreground session active. Ctrl-C stops this installation; stop.sh also works from another session.'
  trap '"$ARTEX_HOME/bin/stop.sh"; exit 0' INT TERM
  while artex_backend_pid >/dev/null; do
    sleep 5
  done
}
