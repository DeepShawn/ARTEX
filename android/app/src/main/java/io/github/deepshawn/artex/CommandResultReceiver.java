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
            text = "Termux 命令退出（" + exitCode + "）。\n" + result.getString("errmsg", "") + "\n" + result.getString("stderr", "") + "\n" + result.getString("stdout", "");
        } else if (!intent.getBooleanExtra("setup_command", false)) {
            text = "本地服务停止命令已完成。";
        } else {
            text = "Termux 命令已结束。若服务未就绪，请打开 Termux 查看日志后重新启动。";
        }
        if (text.length() > 4000) text = text.substring(text.length() - 4000);
        preferences.edit().putString("command_result", text).putString("command_result_id", commandId)
            .putBoolean("command_failed", error != -1 || code != 0).putBoolean("setup_pending", false)
            .putLong("command_result_time", System.currentTimeMillis()).apply();
    }
}
