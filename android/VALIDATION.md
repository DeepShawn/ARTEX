# Android .3 验证记录

日期：2026-10-24。对应源码标签：`android-v0.3.17-android.3`。

## 环境与范围

- 官方 Android Emulator 37.2.12（build 16428233），AOSP Android 9 / API 28 x86_64 系统镜像 revision 4。
- 构建主机没有 KVM，使用 QEMU 纯软件模拟。测试 APK 通过 `ANDROID_RUNTIME_ABI=x86_64` 构建，与 ARM64 发布包使用同一套 Java、初始化脚本和 CGO/Bionic SQLite 驱动。
- 官方 Termux GitHub v0.118.3，PostgreSQL 18.6，Android System WebView 113.0.5672.136。
- ARTEX 后端和数据库运行于模拟器内部的普通 Termux UID，监听模拟器的 `127.0.0.1`；主机通过 ADB 转发访问接口。SELinux 保持 enforcing，没有关闭 seccomp。
- 公开 Release 只提供 ARM64 APK。ARM64 完成交叉编译、Android/Bionic ELF、系统 DNS、16 KB 页对齐、APK 签名和内嵌资源校验；**没有完成 ARM64 实机或 ARM64 模拟器运行验证**。x86_64 测试不能替代 ARM64 运行验证。

## 发现并修复的问题

1. Termux `openssl` 是库包，命令行工具由 `openssl-tool` 提供。旧脚本可能因命令缺失生成空的 `config/postgres.password`，重试时又跳过生成，最终导致 `initdb` 失败。已在实际 Termux 环境复现，补齐依赖并改为暂存、校验、原子写入后，PostgreSQL 初始化成功。仅在尚未建成集群时恢复空密码；已有集群缺失凭据时拒绝重置。
2. modernc 的 Linux syscall 层在 Android x86_64 上触发被 app seccomp 禁止的旧式 `lstat` 调用，后端 SIGSYS。Android 统一改用 CGO/Bionic SQLite，开启 FTS5；同一后端随后通过健康与认证检查。桌面仍使用原有驱动。
3. 大量 apt 下载输出可能覆盖初始化 stderr。命令回调现在分别保留错误和下载日志尾部；`initdb` 失败时也回传其详细日志。

## 已通过

- 实际 Termux 内安装依赖、提取本地运行资源、生成凭据、初始化 PostgreSQL 集群、创建业务数据库并启动 Go 后端。
- `/api/health` 返回正常和 `.3` 版本；首次管理员初始化写入 PostgreSQL；错误密码登录被拒绝，正确密码可登录。
- 未登录访问任务 API 返回 401，携带有效凭据返回 200；生产 HTML 与 JavaScript 资源正常返回。
- 重复初始化保持数据库密码不变。
- 实际 Termux 停止脚本正常关闭 Go 服务与 PostgreSQL，HTTP 接口随即不可用；再次启动后管理员仍已初始化，重启前的 JWT 仍可访问受保护接口，原管理员密码仍可登录。
- 主机隔离回归：软件包配置恢复 3 项、数据库凭据 6 项；两种 SQLite 驱动的流量存储测试通过，覆盖全文搜索和空间回收。
- 主机生命周期夹具：重复安装、重复启动、重启、校验和失败、无关 PID、端口冲突、数据库主版本不匹配、独立停止与数据保留。

## 模拟器专用调整与限制

这些调整只在测试机上使用，不包含在 ARTEX APK、runtime 或初始化脚本中：

- 无图形加速的软件模拟出现 Android 系统服务与界面超时。为防止启动 Watchdog 重启，连接 system_server 调试器并显式恢复 VM；未设置断点或暂停线程。系统 UI、Termux 也使用调试器连接减少系统超时干扰。该环境不适合评价启动速度或长期稳定性。
- 通过主机继承的网络代理和测试 CA 连接官方软件源；关闭 Termux 镜像轮询，只使用已配置的官方源。APT 校验和 TLS 验证保留。
- 最新 x86_64 Termux Python 3.14 的分配器在该镜像触发旧式 `SYS_open` 的 SIGSYS。仅测试环境的 Python 包装器将此调用转为 `openat`；没有关闭系统过滤。这个兼容夹具未随产品分发，ARM64 没有相同的旧式 syscall 编号。
- 原始镜像的 WebView 66 太旧，替换为 AOSP WebView 113；测试安装使用公开 AOSP 测试签名，未改动 ARTEX 发布签名。目标手机也应更新 Android System WebView / Chrome。
- 可选的 Termux 唤醒锁辅助程序在此 x86_64 环境报告 SIGSYS，ARTEX 按设计继续启动；锁屏、厂商省电策略、后台存活仍需 ARM64 实机验证。

没有运行对外扫描、远程 LLM、桌面 Playwright、root 工具或长期压力测试。界面操作和完整 Termux 回调仍受上述软件模拟超时影响，不能据此宣称这些能力已全部通过。

## 重现构建与回归

```sh
python3 android/tests/test-package-bootstrap.py
python3 android/tests/test-database-credential.py
go test ./traffic
CGO_ENABLED=1 go test -tags artex_android_sqlite_test,sqlite_fts5 ./traffic
# 使用 README 中相同的 SDK、NDK 与私有签名配置：
ANDROID_RUNTIME_ABI=x86_64 APAGENT_SKIP_FRONTEND=1 bash android/build.sh
```

安装测试 APK 与官方 Termux 后，启用 `allow-external-apps`，授予 `com.termux.permission.RUN_COMMAND`，再初始化本地服务。实际发行包省略 `ANDROID_RUNTIME_ABI`，默认生成 `arm64-v8a`。
