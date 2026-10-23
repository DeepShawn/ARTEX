#!/usr/bin/env bash
# Autonomous Pentest Agent 安装脚本：① 全部 Docker  ② 本地编译运行
set -euo pipefail
cd "$(cd "$(dirname "$0")" && pwd)"

info(){ printf '\033[36m[*]\033[0m %s\n' "$*"; }
ok(){   printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[!]\033[0m %s\n' "$*"; }
die(){  printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
ask(){  local p="$1" d="${2:-}" a; read -rp "$p${d:+ [$d]}: " a; echo "${a:-$d}"; }
rand(){ head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24; }

# Compose 的单引号值保留 $、&、| 等字面字符；逐行写入避免 sed replacement 注入。
dotenv_set(){
  local name="$1" value="$2" line
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *\\* ]] \
    || die "配置值不能含换行或反斜杠，请在 .env 中手动配置"
  value="${value//\'/\\\'}"
  ( umask 077
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "$name="*) printf "%s='%s'\n" "$name" "$value" ;;
        *) printf '%s\n' "$line" ;;
      esac
    done < .env > .env.tmp
  )
  mv -f .env.tmp .env
}

# ── docker 环境检测 / 自动安装 ───────────────────
ensure_docker(){
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ok "已检测到 docker 与 docker compose"; return
  fi
  warn "未检测到 docker / docker compose"
  case "$(uname -s)" in
    Linux)
      if [ "$(ask '自动安装 Docker? (y/n)' y)" = y ]; then
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker "$USER" || true
        ok "Docker 安装完成（用户组变更需重新登录后免 sudo）"
      else
        die "请自行安装 docker 后重试"
      fi ;;
    Darwin) die "macOS 请安装 Docker Desktop：https://www.docker.com/products/docker-desktop/" ;;
    *)      die "请自行安装 docker 后重试" ;;
  esac
}

# ── ① 全部 Docker ───────────────────────────────
install_docker(){
  ensure_docker
  if [ ! -f .env ]; then
    cp .env.example .env 2>/dev/null || true
    local pw key
    pw="$(ask 'Postgres 密码（回车随机生成）' "$(rand)")"
    [[ "$pw" =~ ^[A-Za-z0-9._~-]+$ ]] \
      || die "密码请使用字母数字或 . _ ~ -；其他密码请手动填写 .env 并设置 URL 编码的 APAGENT_PG_DSN"
    key="$(ask 'ANTHROPIC_API_KEY（可留空，后续在 UI 配）' '')"
    dotenv_set POSTGRES_PASSWORD "$pw"
    dotenv_set ANTHROPIC_API_KEY "$key"
    ok "已生成 .env（POSTGRES_PASSWORD 已设置）"
  else
    info "沿用已存在的 .env"
  fi
  info "拉取 GHCR 镜像并启动（等待数据库与应用就绪）…"
  docker compose pull
  docker compose up -d --wait --wait-timeout 180
  ok "启动完成 → http://localhost:8787"
  info "查看日志：docker compose logs -f apagent"
}

# ── ② 本地编译运行 ──────────────────────────────
install_local(){
  command -v go >/dev/null 2>&1 && go version >/dev/null 2>&1 \
    || die "未检测到 Go 工具链（>=1.26.3）：https://go.dev/dl/"
  command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 \
    || die "完整部署需要 Node.js >=20.9 与 npm，用于构建内嵌前端"
  echo "数据库安装方式："
  echo "  1) 连接已有 PostgreSQL"
  echo "  2) 用 Docker 起一个 PostgreSQL（需要 docker）"
  case "$(ask '选择' 1)" in
    2)
      ensure_docker
      local pw; pw="$(ask 'Postgres 密码（回车随机）' "$(rand)")"
      docker run -d --name apagent-pg -p 127.0.0.1:5432:5432 \
        -e POSTGRES_USER=apagent -e POSTGRES_PASSWORD="$pw" -e POSTGRES_DB=apagent \
        -v apagent-pg:/var/lib/postgresql/data postgres:16-alpine
      local ready=0 attempt
      for attempt in {1..60}; do
        if docker exec apagent-pg pg_isready -U apagent -d apagent >/dev/null 2>&1; then
          ready=1; break
        fi
        sleep 1
      done
      [ "$ready" -eq 1 ] || die "PostgreSQL 启动超时，请检查 docker logs apagent-pg"
      DB_HOST=127.0.0.1 DB_PORT=5432 DB_USER=apagent DB_PASS="$pw" DB_NAME=apagent DB_SSL=disable ;;
    *)
      DB_HOST="$(ask '数据库地址' 127.0.0.1)"
      DB_PORT="$(ask '端口' 5432)"
      DB_USER="$(ask '账号' apagent)"
      DB_PASS="$(ask '密码' '')"
      DB_NAME="$(ask '数据库名' apagent)"
      DB_SSL="$(ask 'sslmode (disable/require)' disable)" ;;
  esac

  # 生成 config.json
  DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_USER="$DB_USER" DB_PASS="$DB_PASS" \
    DB_NAME="$DB_NAME" DB_SSL="$DB_SSL" node <<'JS'
const fs = require("node:fs");
const e = process.env;
fs.writeFileSync("config.json", JSON.stringify({database: {
  host: e.DB_HOST, port: Number(e.DB_PORT), user: e.DB_USER,
  password: e.DB_PASS, dbname: e.DB_NAME, sslmode: e.DB_SSL,
}}, null, 2) + "\n", {mode: 0o600});
JS
  ok "已生成 config.json"

  # go 环境检查
  ok "Go: $(go version)"

  # 内嵌前端需要 node 出静态产物
  info "构建前端静态产物…"
  ( cd web && npm ci && npm run build:static )
  rm -rf server/webui/dist && mkdir -p server/webui/dist && cp -R web/out/. server/webui/dist/
  local build_version=dev
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    build_version="$(git describe --tags --always --dirty)"
    build_version="${build_version#v}"
  fi
  info "编译内嵌单二进制…"
  CGO_ENABLED=0 go build -tags embedui -trimpath \
    -ldflags "-s -w -X main.version=${build_version}" -o apagent.next ./cmd/apagent
  mv -f apagent.next apagent
  ok "编译完成 → ./apagent"

  info "启动…（Ctrl-C 退出）"
  ./start.sh
}

echo "=============================="
echo "  Autonomous Pentest Agent 安装"
echo "  1) 全部 Docker 安装"
echo "  2) 本地运行（go 编译）"
echo "=============================="
case "$(ask '选择' 1)" in
  1) install_docker ;;
  2) install_local ;;
  *) die "无效选择" ;;
esac
