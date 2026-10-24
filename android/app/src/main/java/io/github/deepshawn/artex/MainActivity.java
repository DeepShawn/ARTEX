package io.github.deepshawn.artex;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.PendingIntent;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.Proxy;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Properties;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONObject;

public final class MainActivity extends Activity {
    private static final String BASE_URL = "http://127.0.0.1:8787";
    private static final String TERMUX_PERMISSION = "com.termux.permission.RUN_COMMAND";
    private static final String TERMUX_SETUP = "mkdir -p ~/.termux; touch ~/.termux/termux.properties; if ! grep -q '^allow-external-apps=true$' ~/.termux/termux.properties; then printf '\\nallow-external-apps=true\\n' >> ~/.termux/termux.properties; fi; termux-reload-settings";
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private LinearLayout home;
    private ScrollView homeScroll;
    private WebView web;
    private TextView status;
    private TextView details;
    private TextView resultText;
    private Button setup;
    private Button enter;
    private boolean active;
    private boolean waiting;
    private boolean ready;
    private boolean autoEnter;
    private boolean stopping;
    private boolean setupDispatched;
    private boolean pollRunning;
    private int pendingAction;
    private String lastResultId = "";
    private String runtimeVersion = "";
    private ValueCallback<Uri[]> fileResult;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.rgb(243, 246, 250));
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            view.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets;
        });
        getWindow().setStatusBarColor(Color.rgb(243, 246, 250));
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR);
        LinearLayout toolbar = new LinearLayout(this);
        toolbar.setPadding(dp(12), dp(6), dp(12), dp(6));
        toolbar.setGravity(android.view.Gravity.CENTER_VERTICAL);
        toolbar.setBackgroundColor(Color.rgb(16, 29, 51));
        TextView title = text("ARTEX", 20, Color.WHITE);
        title.setTypeface(null, android.graphics.Typeface.BOLD);
        toolbar.addView(title, new LinearLayout.LayoutParams(0, dp(48), 1));
        Button settings = compactButton("本地服务");
        settings.setOnClickListener(v -> showHome());
        toolbar.addView(settings);
        Button refresh = compactButton("刷新");
        refresh.setOnClickListener(v -> { if (web.getVisibility() == View.VISIBLE) web.reload(); else poll(); });
        toolbar.addView(refresh);
        root.addView(toolbar);
        homeScroll = new ScrollView(this);
        home = new LinearLayout(this);
        home.setOrientation(LinearLayout.VERTICAL);
        home.setPadding(dp(22), dp(24), dp(22), dp(24));
        homeScroll.addView(home);
        root.addView(homeScroll, new LinearLayout.LayoutParams(-1, 0, 1));

        addText("你的手机，本地工作台", 26, Color.rgb(16, 29, 51));
        addText("Android · arm64-v8a · Termux", 14, Color.rgb(87, 103, 125));
        status = addText("正在检查本地服务…", 18, Color.rgb(8, 127, 140));
        details = addText("前端、Go 后端与 PostgreSQL 都运行在这台手机。LLM 使用你在系统中配置的服务。", 15, Color.rgb(65, 81, 103));
        setup = button("初始化 / 启动本地服务", v -> requestCommand(1));
        enter = button("进入工作台", v -> openWorkbench());
        enter.setEnabled(false);
        button("打开 Termux 查看进度", v -> openTermux());
        button("安装与授权说明", v -> showInstructions());
        button("在浏览器打开本地地址", v -> openExternal(BASE_URL));
        button("停止本地服务", v -> requestCommand(2));
        addText("首次准备", 19, Color.rgb(16, 29, 51));
        addText("1. 安装官方 Termux（F-Droid 或 GitHub 稳定版）。\n2. 在 Termux 中启用外部应用调用，再授予本 APK 的运行命令权限。\n3. 点击“初始化 / 启动”，首次安装需要联网；可在 Termux 查看进度。", 15, Color.rgb(65, 81, 103));
        button("复制 Termux 授权配置命令", v -> copySetup());
        addText("默认地址：127.0.0.1:8787。首次进入后设置管理员密码，用户名 APAGENT。基础工具包含 Python、nmap、ripgrep、curl；浏览器自动化及需要 root 的功能受安卓环境限制。\n\n这是实验版，构建环境没有安卓实机或模拟器，手机运行仍需实际验证。卸载 Termux 会删除数据库与工作区，请先备份。", 14, Color.rgb(87, 103, 125));
        resultText = addText("", 13, Color.rgb(126, 57, 39));
        resultText.setTextIsSelectable(true);

        web = new WebView(this);
        WebSettings ws = web.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setAllowFileAccess(false);
        ws.setAllowContentAccess(true);
        ws.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        ws.setSafeBrowsingEnabled(true);
        ws.setSupportMultipleWindows(false);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false);
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (isLocalPage(uri)) return false;
                if (request.isForMainFrame() && request.hasGesture()) openExternal(uri.toString());
                return true;
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (fileResult != null) fileResult.onReceiveValue(null);
                fileResult = callback;
                try { startActivityForResult(params.createIntent(), 20); }
                catch (Exception error) { fileResult.onReceiveValue(null); fileResult = null; toast("未找到文件选择器"); }
                return true;
            }
        });
        web.setVisibility(View.GONE);
        root.addView(web, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);
        root.requestApplyInsets();
        try {
            Properties runtime = new Properties();
            try (InputStream source = getAssets().open("runtime.properties")) { runtime.load(source); }
            runtimeVersion = runtime.getProperty("runtime.version", "");
            if (runtimeVersion.isEmpty()) throw new IllegalStateException("运行文件版本信息缺失");
        } catch (Exception error) {
            setup.setEnabled(false);
            resultText.setText("无法读取运行文件信息：" + error.getMessage());
        }
        if (getSharedPreferences("artex", MODE_PRIVATE).getBoolean("setup_pending", false)) {
            if (AssetService.getRuntimeUrl() != null) {
                waiting = true; autoEnter = true; setup.setEnabled(false);
                setupDispatched = getSharedPreferences("artex", MODE_PRIVATE).getBoolean("setup_dispatched", false);
                status.setText("正在安装 / 启动，请在 Termux 查看进度…");
                if (!setupDispatched) awaitAssetServer(0);
            } else {
                getSharedPreferences("artex", MODE_PRIVATE).edit().putBoolean("setup_pending", false).apply();
                resultText.setText("上一次初始化已中断。请查看 Termux 的执行情况后重试。");
            }
        }
        if (!Arrays.asList(Build.SUPPORTED_ABIS).contains("arm64-v8a")) {
            setup.setEnabled(false);
            details.setText("这个安装包需要 Android 8.0+ 和 arm64-v8a 设备。当前设备不支持 ARM64 运行时。");
        }
    }

    private boolean isLocalPage(Uri uri) {
        return "http".equals(uri.getScheme()) && "127.0.0.1".equals(uri.getHost()) && uri.getPort() == 8787;
    }

    private TextView text(String value, int size, int color) {
        TextView tv = new TextView(this);
        tv.setText(value); tv.setTextSize(size); tv.setTextColor(color); tv.setGravity(android.view.Gravity.CENTER_VERTICAL);
        return tv;
    }
    private TextView addText(String value, int size, int color) {
        TextView tv = text(value, size, color);
        tv.setPadding(0, dp(8), 0, dp(10));
        tv.setLineSpacing(dp(3), 1);
        home.addView(tv, new LinearLayout.LayoutParams(-1, -2));
        return tv;
    }
    private Button button(String value, View.OnClickListener action) {
        Button b = new Button(this); b.setText(value); b.setAllCaps(false); b.setOnClickListener(action);
        home.addView(b, new LinearLayout.LayoutParams(-1, -2));
        return b;
    }
    private Button compactButton(String value) {
        Button b = new Button(this); b.setText(value); b.setAllCaps(false); b.setTextSize(12); b.setMinWidth(0);
        return b;
    }
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private void toast(String value) { Toast.makeText(this, value, Toast.LENGTH_LONG).show(); }

    private void openTermux() {
        Intent launch = getPackageManager().getLaunchIntentForPackage("com.termux");
        if (launch == null) { showInstall(); return; }
        try { startActivity(launch); } catch (Exception error) { toast("无法打开 Termux，请从桌面打开。"); }
    }
    private void openExternal(String url) {
        Uri uri = Uri.parse(url);
        if (!"http".equals(uri.getScheme()) && !"https".equals(uri.getScheme())) return;
        try { startActivity(new Intent(Intent.ACTION_VIEW, uri)); } catch (Exception error) { toast("未找到浏览器"); }
    }
    private void copySetup() {
        getSystemService(ClipboardManager.class).setPrimaryClip(ClipData.newPlainText("Termux 授权配置", TERMUX_SETUP));
        toast("已复制。请在 Termux 粘贴并执行，然后返回 ARTEX。");
    }
    private void showInstall() {
        new AlertDialog.Builder(this).setTitle("先安装 Termux").setMessage("请安装 F-Droid 或 GitHub 官方稳定版 Termux（建议 0.118 或更高）。APK 通过同一台手机的 Termux 运行数据库、后端和工具，无需远程服务器。").setPositiveButton("官方下载安装页", (d, w) -> openExternal("https://github.com/termux/termux-app#installation")).setNegativeButton("关闭", null).show();
    }
    private void showInstructions() {
        new AlertDialog.Builder(this).setTitle("第一次使用").setMessage("1. 安装并打开一次官方 Termux。\n2. 复制下方配置命令，在 Termux 粘贴执行，启用 allow-external-apps。\n3. 返回 ARTEX 点击初始化，授予运行命令权限。通知权限可选。\n4. 首次依赖安装需要联网；Termux 可能请求确认软件源或系统弹窗，请前往完成。\n5. 服务就绪后进入工作台设置密码；在 LLM 配置页填写模型凭据。\n\n只关闭 APK 页面不会停止 Termux 服务。请保留 Termux 通知，长任务需要系统允许其后台运行。仅对已获授权的目标使用工具。").setPositiveButton("复制配置命令", (d, w) -> copySetup()).setNeutralButton("打开 Termux", (d, w) -> openTermux()).setNegativeButton("关闭", null).show();
    }
    private void requestCommand(int action) {
        if (!Arrays.asList(Build.SUPPORTED_ABIS).contains("arm64-v8a")) { toast("需要 arm64-v8a 设备"); return; }
        if (getPackageManager().getLaunchIntentForPackage("com.termux") == null) { showInstall(); return; }
        if (waiting) { toast("初始化仍在进行，请在 Termux 查看或结束当前命令后再试。"); return; }
        if (action == 1 && ready) { openWorkbench(); return; }
        pendingAction = action;
        if (checkSelfPermission(TERMUX_PERMISSION) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[] { TERMUX_PERMISSION }, 10);
            return;
        }
        if (action == 1 && Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED && !getPreferences(MODE_PRIVATE).getBoolean("notificationsAsked", false)) {
            getPreferences(MODE_PRIVATE).edit().putBoolean("notificationsAsked", true).apply();
            requestPermissions(new String[] { Manifest.permission.POST_NOTIFICATIONS }, 11);
            return;
        }
        performAction(action);
    }
    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] grants) {
        super.onRequestPermissionsResult(request, permissions, grants);
        if (request == 10) {
            if (checkSelfPermission(TERMUX_PERMISSION) == PackageManager.PERMISSION_GRANTED) requestCommand(pendingAction);
            else toast("尚未授予运行命令权限。可在系统设置 → ARTEX 权限中授权，再重试。");
        } else if (request == 11) performAction(pendingAction); // Notification denial is not a setup failure.
    }
    private void performAction(int action) {
        if (action == 2) {
            stopping = true; autoEnter = false; ready = false; enter.setEnabled(false);
            showHome(); status.setText("正在停止本地服务…");
            sendTermux("set -eu\nroot=\"$HOME/.local/share/artex\"\nif [ -f \"$root/bin/stop.sh\" ]; then exec bash \"$root/bin/stop.sh\"; else printf '尚未初始化本地运行环境\\n'; fi\n", new String[] { "-s", "--" }, false);
            return;
        }
        if (waiting) { toast("正在安装或启动，请打开 Termux 查看进度。"); return; }
        waiting = true; autoEnter = true; stopping = false; setupDispatched = false; setup.setEnabled(false);
        resultText.setText("");
        lastResultId = "";
        getSharedPreferences("artex", MODE_PRIVATE).edit().remove("command_result").remove("command_result_id")
            .remove("command_result_time").putBoolean("setup_pending", true).putBoolean("setup_dispatched", false).apply();
        status.setText("正在准备本地安装文件…");
        try {
            AssetService.resetAcknowledgement();
            startForegroundService(new Intent(this, AssetService.class));
            awaitAssetServer(0);
        } catch (Exception error) { setupFailed("无法启动初始化服务：" + error.getMessage()); }
    }
    private void awaitAssetServer(int attempt) {
        String url = AssetService.getRuntimeUrl();
        if (url == null) {
            if (attempt > 40) { setupFailed("初始化文件服务未启动，请重试。"); return; }
            handler.postDelayed(() -> awaitAssetServer(attempt + 1), 250);
            return;
        }
        try {
            Properties runtime = new Properties();
            try (InputStream source = getAssets().open("runtime.properties")) { runtime.load(source); }
            String checksum = runtime.getProperty("runtime.sha256", "");
            if (!checksum.matches("[a-fA-F0-9]{64}")) throw new IllegalStateException("运行文件校验信息缺失");
            String script;
            try (InputStream source = getAssets().open("bootstrap.sh")) { script = new String(readAll(source, 200000), StandardCharsets.UTF_8); }
            status.setText("正在安装 / 启动，请在 Termux 查看进度…");
            setupDispatched = sendTermux(script, new String[] { "-s", "--", "--runtime-url", url, "--sha256", checksum,
                "--ready-url", AssetService.getReadyUrl(), "--port", "8787", "--proxy-port", "8788", "--foreground" }, true);
        } catch (Exception error) { setupFailed("无法读取安装文件：" + error.getMessage()); }
    }
    private boolean sendTermux(String script, String[] arguments, boolean setupCommand) {
        try {
            String commandId = UUID.randomUUID().toString();
            Intent result = new Intent(this, CommandResultReceiver.class).setAction(getPackageName() + ".COMMAND_RESULT")
                .setData(Uri.parse("artex-command://result/" + commandId)).putExtra("command_id", commandId)
                .putExtra("setup_command", setupCommand);
            int flags = PendingIntent.FLAG_ONE_SHOT;
            if (Build.VERSION.SDK_INT >= 31) flags |= PendingIntent.FLAG_MUTABLE;
            PendingIntent callback = PendingIntent.getBroadcast(this, (int) (System.nanoTime() & 0x7fffffff), result, flags);
            Intent command = new Intent("com.termux.RUN_COMMAND");
            command.setClassName("com.termux", "com.termux.app.RunCommandService");
            command.putExtra("com.termux.RUN_COMMAND_PATH", "/data/data/com.termux/files/usr/bin/bash");
            command.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arguments);
            command.putExtra("com.termux.RUN_COMMAND_STDIN", script);
            command.putExtra("com.termux.RUN_COMMAND_WORKDIR", "/data/data/com.termux/files/home");
            command.putExtra("com.termux.RUN_COMMAND_BACKGROUND", true);
            command.putExtra("com.termux.RUN_COMMAND_COMMAND_LABEL", setupCommand ? "ARTEX 本地服务" : "停止 ARTEX");
            command.putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", callback);
            getSharedPreferences("artex", MODE_PRIVATE).edit().putString("active_command_id", commandId)
                .putBoolean("setup_pending", setupCommand).remove("command_result").remove("command_result_id")
                .remove("command_result_time").apply();
            lastResultId = "";
            startService(command);
            getSharedPreferences("artex", MODE_PRIVATE).edit().putBoolean("setup_dispatched", setupCommand).apply();
            return true;
        } catch (Exception error) {
            setupFailed("Termux 启动失败：" + error.getMessage() + "。请确认外部应用开关和权限已开启。");
            return false;
        }
    }
    private void setupFailed(String message) {
        waiting = false; autoEnter = false; stopping = false; setupDispatched = false; setup.setEnabled(!runtimeVersion.isEmpty());
        getSharedPreferences("artex", MODE_PRIVATE).edit().putBoolean("setup_pending", false).apply();
        resultText.setText(message); status.setText("本地服务尚未启动");
        stopService(new Intent(this, AssetService.class));
    }
    private void openWorkbench() {
        if (!ready) { toast("请先启动本地服务"); return; }
        homeScroll.setVisibility(View.GONE); web.setVisibility(View.VISIBLE);
        if (web.getUrl() == null) web.loadUrl(BASE_URL + "/");
    }
    private void showHome() { web.setVisibility(View.GONE); homeScroll.setVisibility(View.VISIBLE); }

    private final Runnable repeatPoll = new Runnable() {
        @Override public void run() { if (active) { poll(); handler.postDelayed(this, 3000); } }
    };
    private void poll() {
        if (worker.isShutdown() || pollRunning) return;
        pollRunning = true;
        final String expectedVersion = runtimeVersion;
        worker.execute(() -> {
            boolean healthy = false;
            String version = "";
            try {
                JSONObject health = localJson("/api/health");
                version = health.optString("version");
                if (health.optBoolean("ok") && "apagent".equals(health.optString("service"))) {
                    JSONObject auth = localJson("/api/auth/status");
                    healthy = auth.opt("initialized") instanceof Boolean;
                }
            } catch (Exception ignored) { }
            final boolean found = healthy;
            final String foundVersion = version;
            handler.post(() -> {
                pollRunning = false;
                if (!active) return;
                android.content.SharedPreferences preferences = getSharedPreferences("artex", MODE_PRIVATE);
                String received = preferences.getString("command_result_id", "");
                if (!received.isEmpty() && !received.equals(lastResultId)) {
                    lastResultId = received;
                    resultText.setText(preferences.getString("command_result", ""));
                    stopping = false;
                    if (waiting && !AssetService.isBootstrapReady()) {
                        setupFailed("初始化命令已结束，但没有确认安装完成。\n" + preferences.getString("command_result", ""));
                    } else if (!found) {
                        waiting = false; autoEnter = false; setupDispatched = false;
                        setup.setEnabled(!runtimeVersion.isEmpty());
                        stopService(new Intent(this, AssetService.class));
                    }
                }
                if (waiting && setupDispatched && AssetService.getRuntimeUrl() == null) {
                    setupFailed("初始化文件服务已结束。请查看 Termux 日志后重试；已有数据库不会被删除。");
                }
                if (stopping && !found) stopping = false;
                boolean acknowledged = !waiting || (AssetService.hasServedRuntime() && AssetService.isBootstrapReady());
                ready = found && !expectedVersion.isEmpty() && expectedVersion.equals(foundVersion) && acknowledged && !stopping;
                enter.setEnabled(ready);
                if (ready) {
                    status.setText("本地服务已就绪 · 127.0.0.1:8787");
                    setup.setEnabled(true); waiting = false; setupDispatched = false;
                    preferences.edit().putBoolean("setup_pending", false).apply();
                    stopService(new Intent(this, AssetService.class));
                    if (autoEnter) { autoEnter = false; openWorkbench(); }
                } else if (stopping) {
                    status.setText("正在停止本地服务…");
                } else if (!waiting) {
                    status.setText(found ? "本地运行版本需要更新，请点击初始化" : "本地服务未运行或数据库未就绪");
                    if (web.getVisibility() == View.VISIBLE) showHome();
                }
            });
        });
    }
    private JSONObject localJson(String path) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(BASE_URL + path).openConnection(Proxy.NO_PROXY);
        try {
            connection.setConnectTimeout(1200); connection.setReadTimeout(1200); connection.setInstanceFollowRedirects(false);
            if (connection.getResponseCode() != 200) throw new IllegalStateException("本地接口尚未就绪");
            try (InputStream response = connection.getInputStream()) {
                return new JSONObject(new String(readAll(response, 16384), StandardCharsets.UTF_8));
            }
        } finally { connection.disconnect(); }
    }
    private static byte[] readAll(InputStream stream, int limit) throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        byte[] buffer = new byte[4096]; int count;
        while ((count = stream.read(buffer)) != -1) { if (bytes.size() + count > limit) throw new IllegalStateException("响应过长"); bytes.write(buffer, 0, count); }
        return bytes.toByteArray();
    }
    @Override protected void onResume() { super.onResume(); active = true; handler.post(repeatPoll); }
    @Override protected void onPause() { active = false; handler.removeCallbacks(repeatPoll); super.onPause(); }
    @Override protected void onDestroy() { active = false; handler.removeCallbacksAndMessages(null); worker.shutdownNow(); if (fileResult != null) fileResult.onReceiveValue(null); web.destroy(); super.onDestroy(); }
    @Override public void onBackPressed() { if (web.getVisibility() == View.VISIBLE) { if (web.canGoBack()) web.goBack(); else showHome(); } else super.onBackPressed(); }
    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == 20 && fileResult != null) { fileResult.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result, data)); fileResult = null; }
    }
}
