<div align="center">

# Autonomous Pentest Agent

AI 自主渗透测试系统（Go 后端 + Next.js 前端）


🌐 **在线 Demo**： [https://apagent-demo.vercel.app/](https://apagent-demo.vercel.app/)

📦 **ARTEX 分发渠道**：[GitHub Releases](https://github.com/DeepShawn/ARTEX/releases) 提供内嵌前端的预编译包，Docker 镜像发布到 `ghcr.io/deepshawn/artex`。当前发布版本：**v0.3.17**。

📱 **Android arm64-v8a 实验版**：[APK 下载](https://github.com/DeepShawn/ARTEX/releases/tag/v0.3.17) · [安装说明](android/README.md)。APK 与同一台手机上的 Termux 配合运行后端、PostgreSQL 和工具；无需远程 ARTEX 服务器。需要 Android 8.0+，尚未完成安卓实机验证。

📝 **系统提示词入口**：[配置、拼接与模型调用位置](SYSTEM_PROMPT_ENTRYPOINTS.md)，关键源码已使用「系统提示词入口」注释标注。

</div>

---

## 截图预览

> 完整交互见[在线 Demo](https://apagent-demo.vercel.app/)。

| 仪表盘（总览 / Token 消耗 / 活动流） | 任务列表 |
| :---: | :---: |
| ![仪表盘](screenshots/dashboard.png) | ![任务](screenshots/tasks.png) |

| 任务 · 执行过程（会话 / 工具调用） | 探索链路 |
| :---: | :---: |
| ![执行过程](screenshots/sessions.png) | ![探索链路](screenshots/graph.png) |

| 发现 | 资产 |
| :---: | :---: |
| ![发现](screenshots/findings.png) | ![资产](screenshots/assets.png) |

| 资产覆盖图（力导向布局 · 已测高亮 · 节点折叠展开） |
| :---: |
| ![资产覆盖图](screenshots/assets_test.png) |

| 流量录制 | 人在环路对话 |
| :---: | :---: |
| ![流量](screenshots/traffic.png) | ![对话](screenshots/chat.png) |

| Agent 管理 | LLM 配置 |
| :---: | :---: |
| ![Agent](screenshots/agents.png) | ![LLM](screenshots/llm.png) |

| 拦截审批 | 后端日志 |
| :---: | :---: |
| ![拦截](screenshots/intercept.png) | ![日志](screenshots/logs.png) |


---

## 审批记录详情

全局「审批记录」、任务内「拦截审批」及对话中的审批卡片均支持展开查看详情。展示结构参考
[AegisHook 的审批详情组件](https://github.com/RuoJi6/AegisHook/blob/main/web/src/components/CallDetail.vue)，沿用 Autonomous Pentest Agent 的组件和主题：


## 资产同步（ScopeSentry）

支持从 [ScopeSentry](https://github.com/Autumn-27/ScopeSentry) 直接同步资产数据，免去重复收集：

- 在「**资产同步**」页填 ScopeSentry 的地址与 API Key，接入数据源；
- 按**项目**或**任务**维度选择要同步的目标与资产类型（域名 / 子域 / IP / 端口 / 站点 / 端点…）；
- 一键导入并按公司资产范围归并，直接进入 Autonomous Pentest Agent 的资产图供 agent 探索使用。

---

## 部署

本仓库使用 [DeepShawn/ARTEX Releases](https://github.com/DeepShawn/ARTEX/releases) 与 GHCR 镜像 `ghcr.io/deepshawn/artex`。旧 Docker Hub `autumn27/apagent` 不再使用。

**直接运行预编译包**：在 [v0.3.17](https://github.com/DeepShawn/ARTEX/releases/tag/v0.3.17) 下载对应平台的 zip 和 `SHA256SUMS`，校验并解压；目标机器无需 Go 或 Node.js，但必须能连接 PostgreSQL。Linux amd64 示例：

```bash
curl -fLO https://github.com/DeepShawn/ARTEX/releases/download/v0.3.17/apagent-0.3.17-linux-amd64.zip
curl -fLO https://github.com/DeepShawn/ARTEX/releases/download/v0.3.17/SHA256SUMS
# 只校验下载的这一份包；不要忽略校验失败。
grep '  apagent-0.3.17-linux-amd64.zip$' SHA256SUMS | sha256sum -c -
unzip apagent-0.3.17-linux-amd64.zip
cd apagent-0.3.17-linux-amd64
cp config.example.json config.json   # 按“数据库准备”填写连接信息
./start.sh
```

Windows 下载 `windows-amd64` 包并运行 `start.bat`；macOS 下载对应 `darwin` 包。首次访问 `http://localhost:8787` 设置管理员密码。Docker 一体部署见下方方式二。

### 前置依赖

| 组件 | 要求 | 说明 |
| --- | --- | --- |
| Go（源码构建） | **≥ 1.26.3** | `go.mod` 声明 `go 1.26.3`。Go ≥ 1.21 会自动下载所需工具链，但建议直接装 1.26.3 |
| Node.js（源码构建） | **≥ 20.9** | Next 16 的 `engines` 下限，容器内用 20.x 或 22.x |
| PostgreSQL | **14+（推荐 16）** | 唯一数据存储，**没有 SQLite 回退** |
| `rsync` / `zip` | 可选 | 只有 `build.sh` 打包时需要 |
| 内存 | **≥ 4 GB 可用 + 2 GB swap** | 前端 `next build`（turbopack + React Compiler）很吃内存；不足会被 OOM Killer 杀成 `exit code -9`，日志没有任何报错直接断在半路 |

---

### 方式一：源码编译为单二进制

前端必须先导出成静态文件、再嵌进二进制，**三步不能颠倒**：

```bash
git clone https://github.com/DeepShawn/ARTEX.git
cd ARTEX

# 1) 前端静态导出 → 产出 web/out
cd web && npm ci && npm run build:static && cd ..

# 2) 放进内嵌目录（目录必须存在，且只放 web/out 的内容）
rm -rf server/webui/dist && mkdir -p server/webui/dist && cp -r web/out/. server/webui/dist/

# 3) 编译（-tags embedui 才会把前端打进二进制）
CGO_ENABLED=0 go build -tags embedui -trimpath -o apagent ./cmd/apagent
```

启动：

```bash
cp config.example.json config.json   # 填 database 连接（见下节）
./start.sh                           # → http://localhost:8787
```

> **两个实测坑**
> 1. `-tags embedui` 会 `//go:embed all:webui/dist`。该目录不存在时**编译直接失败**：`pattern all:webui/dist: no matching files found`。所以第 2 步不能省。
> 2. 重复构建别写 `cp -r web/out server/webui/dist` —— 目标目录已存在时会变成 `dist/out/`，页面全 404。要么先 `rm -rf`，要么用 `cp -r web/out/. server/webui/dist/`。

也可以让脚本代劳：`./install.sh` 选 **② 本地运行**，填写数据库后自动构建前端与后端，并通过 `start.sh` 启动；选 **① 全部 Docker** 会使用本仓库的 GHCR 镜像。

编译产物在 `./apagent`（约 39 MB，静态链接、无外部依赖）。想直接 `go run` 调试用 `./dev.sh`（后端 8787 + 流量代理 8788 + 前端 5173）。

首次访问 http://localhost:8787 会自动跳 `/setup` 设置管理员密码（**用户名固定为 `APAGENT`**，不能改）。

### 方式二：Docker Compose（推荐）

从仓库下载 compose、脚本与 skills，设置数据库密码后即可启动应用和 PostgreSQL：

```bash
git clone https://github.com/DeepShawn/ARTEX.git
cd ARTEX
cp .env.example .env
# 编辑 .env，必须填写 POSTGRES_PASSWORD（建议随机字母数字密码）
# 默认镜像 ghcr.io/deepshawn/artex:v0.3.17
# 密码含 @、:、/ 等 URL 特殊字符时，还需填写 URL 编码后的 APAGENT_PG_DSN。
docker compose pull
docker compose up -d --wait --wait-timeout 180
docker compose ps
```

也可执行 `./install.sh` 选 **① 全部 Docker**。应用地址为 `http://localhost:8787`；代理端口仅绑定 `127.0.0.1:8788`。应用健康检查会读取 `/api/auth/status`，同时验证 API 与 PostgreSQL 可用；LLM 可以留空，稍后在 UI 配置。

镜像由版本 tag 触发的 `release` 工作流中的 `docker` 任务发布；使用前确认该任务已成功。首次发布后需将 GHCR 包设为 Public，才能匿名拉取；私有包需先 `docker login ghcr.io`，使用有包读取权限的账号。

`pgdata` 保存数据库，`./data` 保存工作区和流量记录，`authdata` 保存 JWT 签名密钥，`./skills` 保存技能。更新时保留这些目录和卷；不要执行 `docker compose down -v`。从旧镜像升级前先备份数据库、`data/` 与旧容器的 `/app/jwt.key`；若旧密钥只存在容器里，请先复制到 `data/jwt.key`，新版本首次启动会自动迁移到 `authdata`。

已有部署升级时保留原 Compose 项目名（原目录名或 `docker compose -p <原项目名>`）及挂载路径，避免切换到另一组空数据卷。

**自行构建镜像**：`Dockerfile` 是运行镜像，先准备内嵌前端的 Linux 二进制。下面以 amd64 为例，arm64 将路径与 `GOARCH` 一起替换：

```bash
# 先按方式一构建 web/out 并复制到 server/webui/dist
mkdir -p dist/amd64
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -tags embedui -trimpath \
  -ldflags "-s -w -X main.version=0.3.17" -o dist/amd64/apagent ./cmd/apagent
docker build -t apagent:local .
# 在 .env 将 APAGENT_IMAGE=apagent、APAGENT_TAG=local，然后：
docker compose up -d --wait --wait-timeout 180
```

镜像预装 nmap、Playwright Chromium、ripgrep 等运行工具。直接使用 Release 二进制时，按需要在宿主机安装这些工具。

### 方式三：前后端分离（低配机器 / 已有 nginx）

机器编不动内嵌前端时，可以**不嵌 UI**：后端只提供 `/api`，静态站点交给 nginx 托管。后端不带 tag 编译时 UI 路由会返回 404（`server/webui_stub.go` 的预期行为），不影响 API。

```bash
go build -trimpath -o apagent ./cmd/apagent          # 不带 embedui
# 前端单独导出后，把 web/out/ 的内容丢给 nginx 当站点根目录
cd web && npm ci && npm run build:static
```

```nginx
server {
    listen 80;
    root /srv/apagent-web;          # web/out/ 的内容
    index index.html;

    location / {
        try_files $uri $uri/index.html /index.html;   # 静态导出是 route/index.html
    }

    location /api/ {
        proxy_pass http://127.0.0.1:8787;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;         # SSE 必须关缓冲，否则活动流一直转圈
        proxy_read_timeout 3600s;
    }
}
```

生产构建下前端默认走**同源** `/api`（`web/src/lib/api.ts` 的 `sseUrl`），所以这种情况下**不需要**设 `NEXT_PUBLIC_SSE_BASE`。

### 方式四：打包分发给离线机器

本地编好、打包带走，目标机不需要 Go 和 Node：

```bash
./build.sh --release                            # 默认五个平台（Windows 仅 amd64）
APAGENT_TARGETS=linux/arm64 ./build.sh --release  # 只出需要的目标
```

产物：`dist/apagent-<version>-<os>-<arch>.zip` + `SHA256SUMS`。各包包含程序、启动脚本、`skills/`、`config.example.json` 与 README / LICENSE / NOTICE / CHANGELOG；Linux/macOS 包另含 `reset-password.sh`。Windows 程序为 `apagent.exe`、入口为 `start.bat`；其余平台运行 `./start.sh`。目标机解压后先填写 `config.json`。

> 版本号默认取自 `git describe --tags --always --dirty`，也可用 `APAGENT_BUILD_VERSION=v0.3.17 ./build.sh --release` 指定。正式发布应使用对应 tag 的干净源码；`dev` 或带提交后缀的开发版本会禁用页面一键更新。默认发布 Linux amd64/arm64、macOS amd64/arm64、Windows amd64 五个平台。

### 方式五：注册为系统服务（systemd）

```ini
# /etc/systemd/system/apagent.service
[Unit]
Description=Autonomous Pentest Agent
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=apagent
WorkingDirectory=/opt/apagent
ExecStart=/opt/apagent/start.sh -addr :8787 -proxy 127.0.0.1:8788
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload && systemctl enable --now apagent
journalctl -u apagent -f
```

> 用 `start.sh` 而不是直接 `./apagent`：页面「一键更新」换装后靠它重新拉起（退出码 75）。`Restart=always` 与它不冲突（正常停止时脚本返回 0，循环退出）。
> `-proxy` 是**流量录制代理**，默认只监听 `127.0.0.1:8788`，**不要暴露到公网**；不需要录制就传 `-proxy ""` 关掉。

---

### 数据库准备

角色的权限要够建表；库可以自己建，也可以让程序建：

```sql
CREATE USER apagent WITH PASSWORD '换成强密码';
CREATE DATABASE apagent OWNER apagent;   -- 可省略，见下
```

> 省略 `CREATE DATABASE` 也能跑：后端启动时会先连 `postgres` 维护库，发现目标库不存在就自动建（`db.ensureDatabase`）。但**角色必须先存在**，否则连接阶段就失败。

连接配置**二选一**，优先级：`APAGENT_PG_DSN` 环境变量 > `config.json` 的 `database.dsn` > `config.json` 的 `database` 分字段。

```json
// config.json（放在工作目录或可执行文件同级；也可用 APAGENT_CONFIG 指定路径）
{
  "database": {
    "host": "127.0.0.1", "port": 5432,
    "user": "apagent", "password": "换成强密码",
    "dbname": "apagent", "sslmode": "disable"
  },
  "skill_dir": ""
}
```

```bash
# 或者一行环境变量搞定
export APAGENT_PG_DSN='postgres://apagent:pass@127.0.0.1:5432/apagent?sslmode=disable'
```

> 两者都没配时程序**直接启动失败**并打印它检查过的配置文件路径，不会去猜默认值——这是有意设计，避免悄悄连到错误的库。

### 部署后自检

```bash
curl -fsS localhost:8787/api/health        # 检查进程与版本号
curl -fsS localhost:8787/api/auth/status   # 检查 API 与 PostgreSQL；首次 initialized=false
```

判断标准：日志出现 `backend listening on :8787`、以上接口均返回 200、浏览器能打开首页并跳 `/setup`（首次）或 `/login`。`/api/health` 只报告进程状态，数据库是否可用应结合 `/api/auth/status` 判断。

**忘记密码**：Linux/macOS 发布包附带 `./reset-password.sh`，按 `config.json` / `APAGENT_PG_DSN` 连库，本地模式需要 `psql`。Docker 部署在仓库目录执行该脚本并加 `-m docker`。Windows 可在具备 Bash 和 `psql` 的环境中使用仓库里的同名脚本。

### 目录与持久化

| 路径 | 内容 | 说明 |
| --- | --- | --- |
| `data/`（可执行文件同级） | 工作区、流量记录等运行期数据 | 持久化并随数据库一起备份 |
| `jwt.key`（可执行文件同级） | JWT 签名密钥 | Docker 中通过 `/app/jwt.key` 链接保存于 `authdata` 卷；删除会导致所有人掉登录 |
| `skills/` | skill 目录 | 优先级：`APAGENT_SKILL_DIR` > `config.json` 的 `skill_dir` > 可执行文件同级 `skills/` |
| PostgreSQL | 任务 / 双图 / 发现等主数据 | 每次启动幂等重跑 `schema.sql`，**重启即迁移**，无需手动执行 |

> 升级前请备份 `data/`、`skills/`、`jwt.key`（Docker 为 `authdata` 卷）与数据库。数据库结构只向上迁移，**回退版本不会回退表结构**。

---

## 更新升级

> 更新使用本仓库 [Releases](https://github.com/DeepShawn/ARTEX/releases) 或镜像 `ghcr.io/deepshawn/artex`。数据库启动时自动执行幂等迁移；升级前备份 PostgreSQL、`data/`、`skills/` 和 JWT 密钥。Docker 更新保留 `pgdata` 与 `authdata`，不要删除数据卷。

### 方式一：页面一键更新

在 **系统配置** 页（侧边栏「系统配置」→ `/system/settings`）的**版本与更新**卡片里，可以直接检查并安装新版本，无需登录服务器。

点「更新」后：下载当前平台的发布包 → 比对 Release 的 `SHA256SUMS` → 用 `-h` 冒烟测试新二进制 → 暂存为 `apagent.new` → 程序退出，由 `start.sh` / `start.bat` 重新拉起并完成换装。页面会自动等到新版本上线后刷新。

- **失败不会留下坏程序**：校验或冒烟不通过就丢弃暂存件、继续跑当前版本；换装后的新版若连续 3 次启动失败，会自动回滚到 `apagent.old`（失败的那个留作 `apagent.failed` 供排查）。
- **随时可回退**：上一版本保留为 `apagent.old`，卡片上有「回滚到上一版本」。注意数据库结构不会回退。
- **更新会中断正在运行的任务**——更新即重启，请在空闲时进行。
- **开发构建不给更新**：版本号是 `dev` 或 `git describe` 带后缀时禁用，避免正式版覆盖掉本地调试的二进制。
- **Docker 下只换程序、不换镜像**：镜像里的 playwright / nmap 等工具链不会跟着升级，且 `docker compose up -d` 重建容器后会退回镜像自带的版本。要连镜像一起升级仍请用 `docker compose pull apagent && docker compose up -d apagent`。
- 访问 GitHub 需要代理时，在同一页面配置**全局代理**即可，更新链路会走它。更新只从 GitHub 域名下载并强制 HTTPS。

### 方式二：一键更新脚本

```bash
cd ARTEX
./update.sh
```

脚本先可选 `git pull` 拉取最新代码，再让你选 **① Docker 更新** 或 **② 本地编译更新**（与 `install.sh` 对应）：

- **① Docker**：拉取 GHCR 镜像，仅重建应用，等待 API 与数据库健康检查通过。PostgreSQL 应保持运行。
- **② 本地**：重建前端，编译并验证临时二进制，再原子替换 `./apagent`；手动重启进程生效。

> 本地更新先生成 `apagent.next` 再用 `mv` 替换，避免覆盖运行中的文件导致 `Text file busy`；构建失败会保留原二进制。

### 方式三：Docker Compose（手动）

```bash
cd ARTEX
git pull                       # 更新 compose / 脚本（可选）
# 指定版本：在 .env 设 APAGENT_TAG=v0.3.17
docker compose pull apagent
docker compose up -d --no-deps --wait --wait-timeout 180 apagent  # PostgreSQL 保持运行
```

### 方式四：预编译二进制（Releases）

到 [Releases](https://github.com/DeepShawn/ARTEX/releases) 下载新版本 zip 并校验 `SHA256SUMS`，停掉旧进程后替换 `apagent`，按需合并 `skills/`（保留你的 `config.json`、`data/`、`jwt.key` 与自定义技能），重启即可：

```bash
cp <解压目录>/apagent ./apagent.next && mv -f apagent.next apagent
# 按需合并新版 skills，避免覆盖自己修改的同名技能。
./start.sh
```

### 方式五：从源码编译

```bash
git pull
cd web && npm ci && npm run build:static && cd ..
rm -rf server/webui/dist && mkdir -p server/webui/dist && cp -r web/out/. server/webui/dist/
CGO_ENABLED=0 go build -tags embedui -trimpath -o apagent.next ./cmd/apagent
# 先停止原进程或 systemd 服务，再替换并启动。
mv -f apagent.next apagent && ./start.sh
```

> 直接覆盖运行中的 `apagent` 会得到 `Text file busy`，所以先编到 `apagent.next` 再 `mv`（同分区下 `mv` 是原子替换，比 `cp` 安全）。
> 重复构建时务必先 `rm -rf server/webui/dist`，否则 `cp -r web/out server/webui/dist` 会生成 `dist/out/` 导致页面 404。

---

## 配置

**数据库**（`config.json`，或用环境变量 `APAGENT_PG_DSN` 覆盖）：

```json
{
  "database": {
    "host": "127.0.0.1", "port": 5432,
    "user": "apagent", "password": "yourpass",
    "dbname": "apagent", "sslmode": "disable"
  }
}
```

**LLM**：`export ANTHROPIC_API_KEY=sk-...`（或 `OPENAI_API_KEY`），也可在 UI 的「LLM 配置」页填写。
可选：`APAGENT_LLM_PROVIDER` / `APAGENT_LLM_MODEL` / `APAGENT_LLM_BASE_URL` / `APAGENT_LLM_PROXY`。

**并发**：每个任务的 work agent 数在「系统设置」里配置（默认 3）。

**常用参数**：`./start.sh -addr :8787 -proxy :8788`（`-addr` 前端+API，`-proxy` 流量录制代理）。启动脚本会把参数原样透传给 `apagent`。

### 反向代理部署（HTTPS / 只开放 443）

前端和 API/SSE 都由同一个后端端口（默认 `:8787`）提供，实时活动流默认走**同源**地址，因此**无需配置 `NEXT_PUBLIC_SSE_BASE`**，公网只开放 443、把 8787 留在内网即可。

SSE 是长连接 + 持续推送，反代**必须关闭缓冲**，否则浏览器能连上却收不到事件（表现为活动流一直转圈）。Nginx 示例：

```nginx
server {
    listen 443 ssl;
    server_name your.domain.com;
    # ssl_certificate / ssl_certificate_key ...

    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;

        # SSE 关键项：关缓冲、长超时、HTTP/1.1
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
```

> 仅当 SSE 需要走与页面不同的来源（如独立子域）时，才在**构建期**设置 `NEXT_PUBLIC_SSE_BASE`（该变量在 `next build` 时固化进静态包，容器运行时再设无效）。

---



## 开发

### 手动漏洞复测

任务详情的「复测」页签可分页选择本任务的漏洞、查看历次结论和证据，并手动发起复测。启动后保留当前页签，显示转圈图标和「复测中」；确认修复后同步更新漏洞状态。

在漏洞列表每行操作区点击「复测」，或在漏洞详情的「漏洞复测」区域点击「发起复测」，填写可选的修复版本、测试条件或限制，系统会创建独立的复测 Agent 会话，启动后保留当前页面。列表的平铺、按任务分组和资产视图均支持该入口；复测运行时显示转圈图标和「复测中」，需要查看时点击进入对应会话，结束后恢复「复测」。复测无需重新启动原扫描任务，结论分为「仍可复现」「已修复」「无法确认」，每次的结论、证据和会话链接保存在漏洞详情中。

新版后端首次启动会预置可编辑的「漏洞复测」（`retester`）Agent，可在 Agent 管理中配置提示词、LLM、运行预算和工具。默认使用其绑定的 LLM，未绑定则使用全局激活配置。复测会话成功完成且结论为「已修复」时，系统自动将漏洞处置状态改为「已修复」；执行中、失败、停止或其他结论保留原状态。原始证据和报告始终保留。也可在状态下拉菜单中手动选择「已修复」。同一漏洞正在复测时复用已有会话，停止、失败或服务重启后可重新发起。

本版历史记录通过漏洞详情和会话查看，暂未纳入漏洞报告导出或任务归档包，也未自动关联流量包。演示模式只生成明确标注的模拟记录，不请求真实目标。

### 本地运行与测试

```bash
./dev.sh    # 后端(:8787) + 流量代理(:8788) + 前端 next dev(:5173) → http://localhost:5173
```

- 后端：`go run ./cmd/apagent`（不带 `-tags embedui` 则不内嵌前端）
- 前端：`cd web && npm run dev`（`/api` 反代到后端，带热更新）
- 测试：`go test ./...`
- Mock 预览（无后端）：`cd web && NEXT_PUBLIC_MOCK=1 npm run dev`

---

## 系统技术架构

Autonomous Pentest Agent 是一套 **LLM 多 agent 驱动的自主渗透系统**：Go 单体后端（内嵌 Next.js 前端）+ PostgreSQL，agent 能力由 [`norma`](https://github.com/Autumn-27/norma) SDK 提供（`agentcore` / `tool` / `permission` / `harness` / `memory` / `transcript`）。核心是**双图架构**，以及围绕它的两条自主性机制：**worker 间过程级信息交换**与 **planner 多轮共享 todolist 稳定攻击链路**。

### 总体分层

```mermaid
flowchart TB
  subgraph FE["前端 Next.js（go:embed 内嵌单二进制）"]
    UI["仪表盘 · 任务 · 资产 · 覆盖图 · 流量 · 工作空间 · 系统配置"]
  end
  subgraph SRV["server（Go net/http）"]
    API["REST /api/*　JWT 鉴权　SSE"]
    ENG["engine 调度循环"]
    MGR["Manager　任务/引擎/store 生命周期"]
  end
  subgraph AG["agent（norma SDK）"]
    GO["goals　目标分解 + 提取范围"]
    PL["planner　规划者（唯一意图生成者）"]
    WK["worker　执行者 ×N"]
    MA["mainagent　人在环路"]
  end
  subgraph DB["PostgreSQL"]
    AGRAPH["资产图　assets / companies / task_scope"]
    EGRAPH["探索图　exploration_nodes / anchors / activity"]
  end
  subgraph SUB["支撑子系统"]
    PROXY["流量记录代理　MITM + CA 留痕"]
    GUARD["guard / intercept　工具审批门"]
    ENR["enrich　DNS / HTTP 异步补全"]
    EXT["MCP · skills · memory · report"]
  end

  UI -->|HTTP| API
  API --> MGR --> ENG
  ENG --> PL
  ENG --> WK
  API --> MA
  API --> GO
  PL --> DB
  WK --> DB
  MA --> DB
  GO --> DB
  WK -->|"Bash / HTTP 全程留痕"| PROXY
  WK --> GUARD
  WK --> ENR
  PL -.-> EXT
  WK -.-> EXT
  MA -.-> EXT
```

| 层 | 职责 |
| --- | --- |
| **前端** | Next.js 静态导出，`go:embed` 内嵌进单二进制；可视化任务/资产/探索链路/覆盖图，人在环路对话 |
| **server** | `net/http` 路由 + JWT 鉴权 + SSE；`Manager` 托管任务、引擎、DB store 的生命周期 |
| **engine** | 每任务一个 `plannerLoop` + N 个 worker goroutine；意图领取、超时/暂停/drain |
| **agent** | goals / planner / worker / mainagent，`ToolSet` 把双图暴露成 LLM 工具 |
| **db** | 双图的 Postgres 落地（pgx）；schema 随 `go:embed` 每次启动幂等建表 |
| **支撑** | 记录型 MITM 代理、审批门、异步补全、MCP/技能/记忆/报告 |

### 双图架构：探索图 + 资产图

系统把「**目标是什么**」和「**测到了什么程度**」拆成两张相互独立、又通过锚点相连的图：

- **资产图（Asset Graph，全局共享）**：跨任务同一份的资产真值库。节点为 `root_domain / subdomain / ip / service / app / endpoint`，归属公司；域名→子域→服务→端点的父子关系与去重 key 全部由程序计算，agent 只提交原始信息。
- **探索图（Exploration Graph，每任务独立）**：一次任务的“思考与推进”过程。节点为 `goal（目标）/ intent（意图）/ fact（事实）/ finding（漏洞）/ hint（提示）`，靠 `spawns / derived_from / yields / proves` 等边连成**血缘链**，回答“哪个方向派生自哪些事实、产出了什么”。
- **两图靠锚点相连**：`exploration_anchors(node_id, asset_id)` 把意图/事实/漏洞锚定到具体资产上——于是既能从“探索方向”看它打的是哪些资产，也能从“某个资产”反查它在本任务被哪些意图测过、得出过哪些事实。这也支撑了**资产测试覆盖度**与**资产覆盖图**（范围内资产 + 已测高亮）。

```mermaid
flowchart LR
  subgraph EG["探索图（每任务独立 · 推进链）"]
    direction TB
    G["goal 目标"]
    I1["intent 意图 A"]
    F1["fact 事实"]
    I2["intent 意图 B"]
    FD["finding 漏洞"]
    G -->|spawns| I1
    I1 -->|yields| F1
    F1 -->|derived_from| I2
    I2 -->|proves| FD
  end
  subgraph AG["资产图（全局共享 · 真值库）"]
    direction TB
    RD["root_domain"]
    SD["subdomain"]
    SV["service"]
    EP["endpoint"]
    RD --> SD --> SV --> EP
  end
  I1 -. anchor .-> SD
  F1 -. anchor .-> SV
  I2 -. anchor .-> EP
  FD -. anchor .-> EP
```

> 分工：**planner** 读探索图态势、判目标、只在有未覆盖的新方向时派**意图**进 frontier；**worker** 领**一条意图**、用真实工具执行、把新资产/事实/漏洞写回两图后即停。资产图是共享事实，探索图是每任务的推进链。

### 引擎与意图生命周期（一次探索的闭环）

引擎是**事件驱动**的闭环：图一变就唤醒 planner，planner 派意图，worker 领意图执行并写回，写回又触发下一轮——直到目标被证明（`prove_goal`）。

```mermaid
sequenceDiagram
  autonumber
  participant EV as 图变更 debounce
  participant P as planner
  participant FR as frontier 意图队列
  participant W as worker
  participant PX as 记录代理
  participant DB as 双图 + activity

  EV-->>P: 唤醒
  P->>DB: 读态势(graph_overview 预取 + coverage/scope)
  P->>FR: 派 0..N 个意图(带 asset_ids)
  Note over P,FR: 大多数唤醒派 0 个——无新方向即结束
  W->>FR: claimNext 领一条意图
  W->>DB: 取意图 asset_ids 的原始资产作为初始信息
  W->>PX: 真实工具执行(Kali / Bash / HTTP)
  PX-->>W: 响应(全程留痕 + CA 验证)
  W->>DB: 写回 fact / asset / finding + 每步 activity
  DB-->>EV: 图变更
  EV-->>P: 再次唤醒(闭环)
```

### worker 间的过程级信息交换

一次深入的探索里，很多有价值的观察（某个报错、某段响应、某个隐藏参数）出现在一个 worker 的**执行过程**中，却未必被写成正式 fact。为避免重复劳动、让链路上的 worker 能站在彼此的肩膀上，worker 具备**跨 work 检索过程**的能力：

- `search_all_worker_traces(q)`：在**本任务其他 work 的执行过程**里按关键字检索（自动排除自己这条意图的步骤），命中项带 `intent_id`；
- `list_worker_traces` / `get_worker_trace(intent_id, step_ids=[…])`：先看有哪些 work 跑过，再取某个 work 具体几步的完整内容做细节交换。

这样即便探索图上还没有对应的 fact，后续 worker 也能复用他人过程中的观察——**信息在 worker 之间以“执行过程”为粒度流动**，而边界不变（每个 worker 仍只做自己领到的那条意图）。

```mermaid
flowchart LR
  WA["worker A（意图 #12）"] -->|"每步 activity"| ACT[("探索图 · activity 过程库")]
  WB["worker B（意图 #34）"] -->|"每步 activity"| ACT
  WC["worker C（意图 #56）"] ==>|"1) search_all_worker_traces(q)"| ACT
  ACT ==>|"2) 命中 A/B 的步骤（排除自己）"| WC
  WC ==>|"3) get_worker_trace(id, step_ids)"| ACT
  ACT ==>|"4) 返回完整过程内容"| WC
```

### planner 多轮共享 todolist → 稳定的攻击链路

真实攻击链往往是**有前后依赖的多步序列**（如：发现注入点 → 拿到凭据 → 横向 → 提权），一次性把这些并行派下去只会乱套。planner 因此持有一份**按任务保留、跨唤醒共享的规划待办（todolist）**：

- planner 是事件驱动的——图一变就被唤醒，但**每次唤醒是全新会话**；共享的 todolist 让它把一条串行利用链**记录一次**、然后在后续多轮里**按依赖逐步派意图**，而不是把整条链在一轮里全部前置展开；
- 每轮只对「前置步骤已完成、其依赖的 fact 已存在」的下一步派意图，并随进展更新清单（把已被 fact 满足的步骤标完成）。

```mermaid
flowchart TB
  subgraph TODO["共享 todolist（按任务保留 · 跨唤醒常驻）"]
    direction LR
    T1["1 注入点　[已完成]"]
    T2["2 取凭据　[进行中]"]
    T3["3 横向　[待前置]"]
    T4["4 提权　[待前置]"]
    T1 -.前置满足.-> T2 -.-> T3 -.-> T4
  end
  R1["第 1 轮唤醒　派意图①"] --> T1
  R2["第 2 轮（①产出 fact）　派意图②"] --> T2
  R3["第 3 轮（②产出 fact）　派意图③"] --> T3
```

于是攻击链在“事件驱动 + 无状态会话”的环境下依然**稳定推进、不重复、不错序**——这是 Autonomous Pentest Agent 能自主走完多步利用链的关键。

---

## 交流群

扫码关注微信公众号 **SecSentry**，在公众号后台私信即可入群交流。

<div align="center">

<img src="screenshots/wx.png" alt="微信公众号 SecSentry" width="480" />

</div>

---
## 参考

https://github.com/oritera/Cairn


## 许可与免责声明

### 开源协议

本项目采用 **GNU Affero General Public License v3.0（AGPL-3.0）** 授权，完整条款见仓库根目录的 [LICENSE](LICENSE) 文件。

这意味着任何人都可以自由使用、修改和分发本项目，但**衍生作品必须同样以 AGPL-3.0 开源**；特别地，**若你修改本项目并通过网络（如部署为在线服务）向用户提供，也必须向这些用户公开对应的完整源码**。

> ⚠️ **重要提示**：开源协议本身不限制软件的使用用途。以下的「使用限制」与「免责声明」是作者对使用者的额外约定与郑重声明，请务必遵守。

**Autonomous Pentest Agent 仅供个人学习、代码研究与本地技术验证使用，不得用于对任何线上系统或网站发起实际测试。**

### 允许使用范围

- 仅可用于**阅读、学习与研究本项目源码**，以及在**本地隔离环境**中进行技术原理验证；
- 适用于个人学习、学术研究、代码审阅等非攻击性用途。

### 禁止事项

- **严禁使用本工具对任何网站、线上服务或联网系统发起扫描、探测、利用或攻击**（无论是否获得授权、是否为自有资产）；
- 严禁将本工具用于任何实际的渗透测试、攻防对抗或生产环境；
- 严禁将本工具用于非法入侵、数据窃取、勒索、拒绝服务或任何破坏性、犯罪性活动；
- 严禁利用本工具从事违反所在国家/地区法律法规的行为。

### 合规责任

使用者须自行遵守所在国家/地区关于网络安全、数据保护与计算机犯罪的全部法律法规（在中国大陆包括但不限于《网络安全法》《数据安全法》《个人信息保护法》及相关司法解释）。**因使用本工具产生的一切法律责任与后果，均由使用者自行承担。**

### 免责声明

本项目按“现状（AS IS）”提供，不附带任何明示或默示的担保。作者及贡献者不对使用本工具（无论使用方式是否得当）所导致的任何直接或间接损失、数据丢失、系统损坏或法律纠纷承担责任。**下载、安装或使用本项目，即表示你已阅读、理解并同意上述全部条款。**

---

## Attribution / 致谢

Autonomous Pentest Agent is a rebranded derivative of **ARTEX**, originally created by
[Autumn-27](https://github.com/Autumn-27) and licensed under **AGPL-3.0**. The original
authorship and version history are preserved in [`CHANGELOG.md`](CHANGELOG.md) and
[`LICENSE`](LICENSE). Agent capabilities are provided by the
[`norma`](https://github.com/Autumn-27/norma) SDK.
