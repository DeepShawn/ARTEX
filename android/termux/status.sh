#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
artex_init
running=0
if pid="$(artex_pg_pid)"; then
  artex_info "PostgreSQL: running (PID $pid, 127.0.0.1:$ARTEX_PG_PORT)"
else
  artex_info 'PostgreSQL: stopped'
fi
if pid="$(artex_backend_pid)"; then
  artex_info "Backend: running (PID $pid, 127.0.0.1:$ARTEX_PORT)"
  if curl --noproxy '*' -fsS --max-time 5 "http://127.0.0.1:$ARTEX_PORT/api/auth/status" >/dev/null; then
    artex_info 'API and database: ready'
    running=1
  else
    artex_info 'API or database: not ready'
  fi
else
  artex_info 'Backend: stopped'
fi
artex_info "Installation: $ARTEX_HOME"
artex_info "Logs: $ARTEX_LOGS"
[[ "$running" == 1 ]]
