package io.github.deepshawn.artex;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;

public final class CommandResultReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        String commandId = intent.getStringExtra("command_id");
        android.content.SharedPreferences preferences = context.getSharedPreferences("artex", Context.MODE_PRIVATE);
        if (commandId == null || !commandId.equals(preferences.getString("active_command_id", ""))) return;
        Bundle result = intent.getBundleExtra("result");
        int error = result == null ? 0 : result.getInt("err", -1);
        int code = result == null ? Integer.MIN_VALUE : result.getInt("exitCode", Integer.MIN_VALUE);
        String text;
        if (result == null) {
            text = "Termux 未返回命令结果，请打开 Termux 查看执行情况。";
        } else if (error != -1 || code != 0) {
            String exitCode = code == Integer.MIN_VALUE ? "未知" : String.valueOf(code);
            String message = result.getString("errmsg", "");
            String stderr = result.getString("stderr", "");
            String stdout = result.getString("stdout", "");
            String log = message + "\n" + stderr + "\n" + stdout;
            String hint = "";
            if (log.contains("allow-external-apps")) {
                hint = "Termux 尚未允许外部应用调用。点击“复制 Termux 授权配置命令”，到 Termux 粘贴执行后重试。\n";
            } else if (log.contains("PostgreSQL initialization failed")) {
                hint = "PostgreSQL 数据库初始化失败。请查看下方错误详情；完整日志保存在 Termux 的 ~/.local/share/artex/logs/initdb.log。\n";
            } else if (log.contains("conffile prompt") || log.contains("dpkg was interrupted") || log.contains("dpkg: error processing") || log.contains("[ARTEX] Package")) {
                hint = "Termux 软件包安装未完成。请在 Termux 执行：\ndpkg --configure -a\napt --fix-broken install\n遇到配置文件询问时按回车保留现有配置，然后返回 ARTEX 重试。\n";
            }
            // Keep stderr independently: long apt stdout must not hide initdb errors.
            text = "Termux 命令退出（" + exitCode + "）。\n" + hint + tail(message, 400)
                + (stderr.isEmpty() ? "" : "\n错误详情：\n" + tail(stderr, 2200))
                + (stdout.isEmpty() ? "" : "\n安装日志：\n" + tail(stdout, 1200));
        } else if (!intent.getBooleanExtra("setup_command", false)) {
            text = "本地服务停止命令已完成。";
        } else {
            text = "Termux 命令已结束。若服务未就绪，请打开 Termux 查看日志后重新启动。";
        }
        preferences.edit().putString("command_result", text).putString("command_result_id", commandId)
            .putBoolean("command_failed", error != -1 || code != 0).putBoolean("setup_pending", false)
            .putLong("command_result_time", System.currentTimeMillis()).apply();
    }

    private static String tail(String value, int limit) {
        return value.length() <= limit ? value : "…（仅显示日志末尾）\n" + value.substring(value.length() - limit);
    }
}
