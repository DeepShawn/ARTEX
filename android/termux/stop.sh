#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/common.sh"
artex_init
backend_only=0
case "${1:-}" in
  '') ;;
  --backend-only) backend_only=1 ;;
  *) artex_die 'Usage: stop.sh [--backend-only]' ;;
esac
artex_lock
artex_stop_backend
if [[ "$backend_only" == 0 ]]; then
  if artex_pg_pid >/dev/null; then
    artex_info 'Stopping this installation PostgreSQL cluster...'
    pg_ctl -D "$ARTEX_PGDATA" -m fast -w -t 60 stop 8>&- 9>&- \
      || artex_die 'PostgreSQL did not stop cleanly; inspect its log. No unrelated process was killed.'
  fi
  if command -v termux-wake-unlock >/dev/null 2>&1; then
    termux-wake-unlock || true
  fi
fi
artex_info 'Stopped. Database, workspace, skills and JWT key were preserved.'
