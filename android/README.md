# ARTEX Android 本地运行（实验版）

这是面向 **Android 8.0 及更新系统、arm64-v8a** 手机的 Android 界面，与同一台手机上的 Termux 配合运行。Go 后端、PostgreSQL 和命令行工具在 Termux 中执行，APK 使用 WebView 打开手机本地的 ARTEX 页面。它不要求另一台服务器，也不是把桌面 Linux 二进制直接当成 Android 程序运行。

**当前没有 Android 实机或模拟器运行验证。** 构建成功或 APK 签名校验通过不代表已验证手机上的权限授权、Termux 命令回调、数据库启动、WebView 或锁屏运行。请按本文最后的检查项在设备上验证；具体构建结果以对应 Release 说明为准。

## 安装与首次启动

1. 从 [F-Droid](https://f-droid.org/packages/com.termux/) 或 [Termux 官方 GitHub Releases](https://github.com/termux/termux-app/releases) 安装最新稳定版 Termux，并先打开一次，等待它完成基础环境初始化。推荐使用这两个来源的最新稳定版，避免旧版或功能不同的发行渠道。
2. 在 Termux 中启用外部命令接口。编辑 `~/.termux/termux.properties`，确保其中有 `allow-external-apps = true`，然后执行 `termux-reload-settings`。没有文件时可以先创建：

   ```sh
   mkdir -p ~/.termux
   touch ~/.termux/termux.properties
   # 删除旧值后写入，避免重复配置产生歧义。
   sed -i '/^[[:space:]]*allow-external-apps[[:space:]]*=/d' ~/.termux/termux.properties
   printf '\nallow-external-apps = true\n' >> ~/.termux/termux.properties
   termux-reload-settings
   ```

3. 安装对应 Release 的 Android APK，并在 ARTEX 应用中授权「在 Termux 环境中运行命令」。如系统没有显示授权窗口，进入 Android 设置 → 应用 → ARTEX → 权限，查找附加权限中的 Termux 命令权限。Termux 必须先安装，这项权限才有提供者。
4. 由你点击初始化或启动操作后，APK 才会向 Termux 发送安装依赖、准备数据库和启动服务的命令。首次初始化需要联网下载 Termux 软件包，可能耗时较长；保留 Termux 的运行通知，必要时打开 Termux 查看进度。
5. 服务就绪后，在 APK 中打开本地页面。首次访问按页面提示设置管理员密码，用户名固定为 `APAGENT`。LLM 可稍后在界面中配置；使用远程模型时仍需要网络与相应 API 凭据。

Termux 的 `RUN_COMMAND` 接口从 0.95 提供，本文使用的标准输入和命令结果回调需要 **Termux ≥ 0.109**；实际使用建议选择最新稳定版。ARTEX APK 是独立应用，不使用 Termux 的共享用户身份，也不需要与 Termux 使用相同签名。若另外安装 Termux:API 等官方插件，它们与 Termux 必须来自相同发行来源，不能混装 F-Droid 与 GitHub 签名的插件。

当前推荐 `artex-0.3.17-android.2-arm64-v8a.apk`（versionCode 3），与 Windows、Linux、macOS 构建统一发布在 [v0.3.17 Release](https://github.com/DeepShawn/ARTEX/releases/tag/v0.3.17)，并附带 SHA256 校验文件。`.2` 修复后台安装 OpenSSL 时配置确认中断的问题，沿用 `.1` 的签名，可直接覆盖安装。后续覆盖安装 APK 需要使用相同签名；不要为了绕过签名冲突而先删除 Termux。Android 运行时与桌面平台的发布包不同，不应通过桌面版压缩包覆盖手机上的可执行文件。

### 安装失败后的恢复

如果出现 `RunCommandService requires allow-external-apps`，按上面的第 2 步在 Termux 内执行授权配置命令；这个开关不能由 ARTEX 跨应用沙箱自行写入。

如果旧版安装日志出现 `openssl.cnf`、`end of file on stdin at conffile prompt`，说明软件包要求确认配置文件，但后台命令没有可交互的标准输入。安装 `.2` 后再次初始化会保留已有配置并尝试恢复中断的配置。也可以先在 Termux 手工修复：

```sh
dpkg --configure -a
apt --fix-broken install
```

遇到 `Y/I/N/O/D/Z` 配置文件询问时，按回车使用默认 `N`，保留现有配置。完成后返回 ARTEX 再次点击初始化。`-y` 只回答 apt 的确认，不会替 dpkg 回答这种问题；新版单独传入 `--force-confold` 并设置非交互环境。不要删除 Termux 数据或 PostgreSQL 目录。

## 本地运行方式与权限

```text
ARTEX APK / WebView ──本机回环 HTTP── Go 后端
       │                              │
       └──用户点击 → RUN_COMMAND── Termux ── PostgreSQL / 工具
```

初始化期间，APK 通过带随机访问令牌的本机 HTTP 地址把运行资源提供给 Termux，并由初始化脚本校验 SHA256。应用界面通过 `127.0.0.1` 访问后端。数据库与应用均应只监听回环地址；这套默认配置不用于向局域网或公网提供服务。

默认端口为应用 `127.0.0.1:8787`、流量代理 `127.0.0.1:8788`、PostgreSQL `127.0.0.1:15432`。Termux 管理脚本位于 `android/termux/`，安装后可在 Termux 中手动查看或控制：

```sh
"$HOME/.local/share/artex/bin/status.sh"
"$HOME/.local/share/artex/bin/start.sh" --foreground
# 重启后端并保留本次 Termux 任务：
"$HOME/.local/share/artex/bin/start.sh" --restart --foreground
# 在另一个 Termux 会话中停止：
"$HOME/.local/share/artex/bin/stop.sh"
```

APK 的初始化使用 `--foreground`，让 Termux 命令任务在后端运行期间保持存活；界面另外检查 API、数据库和安装完成确认，不会把长驻命令尚未退出当成初始化失败。手动启动不带 `--foreground` 时会启动后端后返回终端。停止脚本只管理本安装的后端与 PostgreSQL；不要改用全局 `pkill postgres`，以免影响手机上其它数据库。

必需的是 APK 的网络权限、`com.termux.permission.RUN_COMMAND` 权限，以及用户在 Termux 中启用 `allow-external-apps`。运行资源和数据库使用 Termux 私有目录，正常初始化不需要共享存储权限，也不需要「显示在其他应用上层」。APK 不会自动安装 Termux，不会在打开应用时自动安装依赖或执行测试任务；扫描任务由你进入 ARTEX 后明确创建并启动。

Android 的后台执行策略仍然适用。保留一个 Termux 会话及其前台服务通知，并根据手机系统设置允许 Termux 在后台运行。Android 12 及更新系统可能限制子进程数量或终止高 CPU 占用的进程；厂商省电策略也可能终止服务。唤醒锁或取消电池优化不能保证进程永久存活，不应把手机本地运行视为无人值守服务器。

## 工具范围与数据

Android/Termux 的工具能力取决于设备、软件包和系统权限。普通应用没有 root 或原始套接字能力；部分 nmap 模式、抓包、Docker、systemd，以及桌面版 Playwright/Chromium 的安装与运行不能照搬桌面部署。未安装或不受支持的工具会影响相关任务，不能把界面可打开等同于全部渗透测试工具已可用。

默认安装根目录为 Termux 中的 `$HOME/.local/share/artex`，可通过脚本的 `ARTEX_HOME` 覆盖。其下 `postgres/` 保存数据库，`data/` 保存工作区，`skills/` 保存技能，`config/` 保存连接配置与数据库密码，`logs/` 保存日志，根目录的 `jwt.key` 保存 JWT 签名密钥。

`docs/SYSTEM_PROMPT_ENTRYPOINTS.md` 标出系统提示词的配置、拼接和模型调用入口；同一 `docs/` 目录还保留许可证、源码地址和部署说明。

这些文件位于 Termux 的私有存储中。**卸载 Termux 或清除其应用数据会删除这些内容。** 升级和重新初始化应保留已有数据库；不要通过删除数据目录来解决启动问题。迁移手机或重装前，备份 PostgreSQL（例如使用 `pg_dump`）、工作区、自定义技能与 JWT 密钥，并保存恢复方法。

Termux 软件包升级若改变 PostgreSQL 主版本，管理脚本会保留旧集群并拒绝直接启动，不会自动清空或重新初始化数据库；需要先备份，再按 PostgreSQL 的升级流程迁移。

APK 自身的数据与 Termux 数据属于不同应用沙箱。卸载界面 APK 不等于自动卸载 Termux 或清除其运行数据。需要停止服务时使用明确的停止操作；从最近任务中划掉界面不能作为数据库已安全停止的判断依据。

## 设备验证

此版本尚未完成以下实机验证。首次使用时建议只验证初始化、登录与空任务列表，不直接启动扫描：

- 未安装 Termux、未授权命令权限、未启用 `allow-external-apps` 时，应用应给出可操作的提示，不能一直显示启动中。
- 点击初始化后能看到依赖准备结果；失败时能查看退出码和错误信息。再次初始化应保留数据库与已有登录设置。
- 后端健康接口与 `/api/auth/status` 均正常返回，WebView 能显示首次设置页、登录页和生产 JavaScript 资源。
- 关闭并重新打开界面后可重新连接已有服务，不重复启动数据库或占用同一端口。
- 明确停止后服务退出；再次启动保留管理员密码、任务数据与 JWT 密钥。
- 锁屏、切换应用、省电模式及系统回收进程后的界面状态能够反映实际服务状态。任何系统造成的终止都不能显示为仍在正常运行。

接口与系统行为参考：[Termux RUN_COMMAND 文档](https://github.com/termux/termux-app/wiki/RUN_COMMAND-Intent)、[Termux 安装说明](https://github.com/termux/termux-app#installation)、[Android 11 包可见性要求](https://github.com/termux/termux-app/wiki/Termux-Libraries#target-sdk-30-package-visibility)。

### 从源码构建 APK

构建主机使用 Linux x86_64、Go 1.26.10、Node.js 22、Java 21，以及 `curl`、`unzip`、`zip`、GNU `tar`、`sha256sum`、Python 3。Java 必须包含编译器与打包模块；完整 JDK 可直接使用，部分发行版的 JRE 也可用 `java com.sun.tools.javac.Main -version` 验证。构建过程不依赖 Gradle 或 Android Studio。

`android/prepare-toolchain.sh` 从 Google 官方下载并校验固定版本的 Android SDK Build Tools 35.0.1、Android 35 平台与 NDK r28c。首次下载约 848 MB，解包与缓存约占 3 GB。NDK 用于将 Go 后端交叉编译为真正的 Android arm64 程序；开启 CGO 使用 Android 系统 DNS，并按 16 KB 内存页要求链接。APK 中的 ARM64 标记库使 Android 安装器识别 `arm64-v8a`。这与手机端运行时工具的安装过程是两套独立流程。

首次构建前，请在仓库外准备自己的发布 keystore。私钥与密码文件应保持私密并独立备份：后续 APK 升级必须使用同一签名密钥。构建脚本不会生成或发布私钥，也不会把它复制进 APK。示例变量只包含文件路径，不含密码值：

```bash
export ANDROID_SDK_ROOT="$HOME/.cache/artex/android-sdk"
export ANDROID_KEYSTORE="/private/artex-release.p12"
export ANDROID_KEYSTORE_PASSWORD_FILE="/private/keystore-password.txt"
export ANDROID_KEY_ALIAS=artex

bash android/prepare-toolchain.sh
APAGENT_BUILD_VERSION=0.3.17-android.2 ANDROID_VERSION_CODE=3 \
  APAGENT_PACKAGE_DIR="$PWD/dist/android-v0.3.17" bash android/build.sh
python3 android/verify-apk.py dist/android-v0.3.17/artex-0.3.17-android.2-arm64-v8a.apk
```

密码文件应仅有一行，并设为仅本人可读；也可用 `ANDROID_KEYSTORE_PASSWORD` 环境变量提供密码。只有私钥密码与 keystore 密码不同时，才额外设置 `ANDROID_KEY_PASSWORD_FILE` 或 `ANDROID_KEY_PASSWORD`。`GO=/path/to/go` 可选择 Go 编译器。已有经过确认的生产前端导出时，可设置 `APAGENT_SKIP_FRONTEND=1` 复用 `server/webui/dist`；默认会重新安装前端依赖并导出生产页面。

脚本生成签名 APK 与其 `.sha256` 文件，并在 `android/app/src/main/assets/` 生成 runtime 压缩包、元数据和 bootstrap。它们及 `android/build/` 均被 Git 忽略。runtime 包内含程序、内置 skills、Termux 脚本、部署说明、`LICENSE`、`NOTICE` 与 `SOURCE.txt`；APK 也直接附带许可证、署名和源码地址。Android 版本默认对应标签 `android-v<Android版本>`（本版为 `android-v0.3.17-android.2`），可通过 `APAGENT_SOURCE_REF` 指定其他源码标签。原始四端核心源码仍为 `v0.3.17`。

可在有 `dpkg` 和 `dpkg-deb` 的 Linux 主机运行 `python3 android/tests/test-package-bootstrap.py`，用隔离的软件包根目录复现配置确认 EOF，并验证后台升级保留配置、恢复中断、修复依赖三个分支。测试不会配置主机软件包，也不能代替 Android 实机验证。

发布时应先提交源码，再构建对应版本。SDK/NDK 的版本与下载 SHA256 固定；`SOURCE_DATE_EPOCH` 可显式指定 runtime 压缩包的时间，默认取当前提交时间，无 Git 元数据的源码压缩包则使用 0。完整 APK 的二进制内容还会受 Java/Go 版本、签名密钥与打包文件时间影响，因此不宣称不同环境下必然逐字节相同。源码与构建脚本可从该版本的 GitHub 标签或 Release 自动提供的源码压缩包取得。
