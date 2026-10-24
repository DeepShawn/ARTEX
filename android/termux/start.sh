#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
artex_init
foreground=0 restart=0
for arg in "$@"; do
  case "$arg" in
    --foreground) foreground=1 ;;
    --restart) restart=1 ;;
    *) artex_die 'Usage: start.sh [--restart] [--foreground]' ;;
  esac
done
artex_lock
[[ -x "$ARTEX_RUNTIME/apagent" ]] || artex_die 'Missing backend runtime; run bootstrap.sh.'
artex_database_env
artex_ensure_postgres
if [[ "$restart" == 1 ]]; then
  artex_stop_backend
fi

if pid="$(artex_backend_pid)"; then
  if curl --noproxy '*' -fsS --max-time 5 "http://127.0.0.1:$ARTEX_PORT/api/auth/status" >/dev/null; then
    artex_info "Already running (PID $pid): http://127.0.0.1:$ARTEX_PORT"
    [[ "$foreground" == 0 ]] || artex_hold_foreground
    exit 0
  fi
  artex_die 'The backend process exists but its database/API is not ready; inspect logs before restarting.'
fi
artex_check_port_free "$ARTEX_PORT" || exit 1
proxy_addr=''
if [[ "$ARTEX_PROXY_PORT" != 0 ]]; then
  artex_check_port_free "$ARTEX_PROXY_PORT" || exit 1
  proxy_addr="127.0.0.1:$ARTEX_PROXY_PORT"
fi

# Termux owns the process and files; no root, desktop shell or shared-storage execution.
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock || artex_info 'Could not acquire a wake lock; check Termux battery settings.'
fi
cd -- "$ARTEX_HOME"
nohup "$ARTEX_RUNTIME/apagent" -addr "127.0.0.1:$ARTEX_PORT" \
  -proxy "$proxy_addr" -data "$ARTEX_HOME/data" \
  >> "$ARTEX_LOGS/apagent.log" 2>&1 < /dev/null 8>&- 9>&- &
pid=$!
printf '%s\n' "$pid" > "$ARTEX_RUN/apagent.pid"
for attempt in {1..90}; do
  kill -0 "$pid" 2>/dev/null || artex_die "Backend exited; inspect $ARTEX_LOGS/apagent.log"
  # nohup may not have exec'ed apagent on the first scheduler tick yet.
  if ! artex_backend_pid >/dev/null; then
    sleep 1
    continue
  fi
  if curl --noproxy '*' -fsS --max-time 2 "http://127.0.0.1:$ARTEX_PORT/api/auth/status" >/dev/null 2>&1; then
    # Health is checked on the process we started, not an arbitrary occupied port.
    artex_backend_pid >/dev/null || artex_die 'Backend exited during its readiness check.'
    artex_info "Ready: http://127.0.0.1:$ARTEX_PORT"
    artex_info "Logs: $ARTEX_LOGS/apagent.log"
    [[ "$foreground" == 0 ]] || artex_hold_foreground
    exit 0
  fi
  sleep 1
done
artex_die "Backend readiness timed out; inspect $ARTEX_LOGS/apagent.log (process was left running)."
