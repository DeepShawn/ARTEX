package io.github.deepshawn.artex;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Exposes only the bundled runtime, on loopback, during user-requested setup. */
public final class AssetService extends Service {
    private static volatile String runtimeUrl;
    private static volatile boolean servedRuntime;
    private static volatile boolean bootstrapReady;
    private ServerSocket listener;
    private final ExecutorService clients = Executors.newFixedThreadPool(2);
    private final Handler handler = new Handler(Looper.getMainLooper());
    public static String getRuntimeUrl() { return runtimeUrl; }
    public static boolean hasServedRuntime() { return servedRuntime; }
    public static boolean isBootstrapReady() { return bootstrapReady; }
    public static void resetAcknowledgement() { servedRuntime = false; bootstrapReady = false; }
    public static String getReadyUrl() {
        String url = runtimeUrl;
        return url == null ? null : url.substring(0, url.lastIndexOf('/') + 1) + "ready";
    }

    @Override public void onCreate() {
        super.onCreate();
        servedRuntime = false;
        bootstrapReady = false;
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel("artex-setup", "本地运行环境初始化", NotificationManager.IMPORTANCE_LOW));
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification notification = new Notification.Builder(this, "artex-setup").setSmallIcon(R.drawable.ic_artex).setContentTitle("ARTEX 正在准备本地环境").setContentText("正在向本机 Termux 提供运行文件，完成后自动结束。").setContentIntent(open).setOngoing(true).build();
        startForeground(1, notification);
        try {
            byte[] random = new byte[24];
            new SecureRandom().nextBytes(random);
            StringBuilder secret = new StringBuilder();
            for (byte b : random) secret.append(String.format("%02x", b & 255));
            final String route = "/" + secret + "/runtime.tar.gz";
            listener = new ServerSocket(0, 4, InetAddress.getByName("127.0.0.1"));
            runtimeUrl = "http://127.0.0.1:" + listener.getLocalPort() + route;
            new Thread(() -> {
                while (!listener.isClosed()) {
                    try {
                        Socket client = listener.accept();
                        clients.execute(() -> serve(client, route));
                    } catch (Exception error) {
                        if (!listener.isClosed()) stopSelf();
                        break;
                    }
                }
            }, "artex-runtime-assets").start();
            handler.postDelayed(this::stopSelf, 30 * 60 * 1000L);
        } catch (Exception error) {
            runtimeUrl = null;
            stopSelf();
        }
    }

    private void serve(Socket client, String route) {
        try (Socket socket = client) {
            socket.setSoTimeout(10000);
            BufferedReader reader = new BufferedReader(new InputStreamReader(socket.getInputStream(), StandardCharsets.US_ASCII));
            String first = reader.readLine();
            int length = first == null ? 0 : first.length();
            String header;
            while ((header = reader.readLine()) != null && !header.isEmpty()) {
                length += header.length();
                if (length > 8192) return;
            }
            OutputStream out = socket.getOutputStream();
            String readyRoute = route.substring(0, route.lastIndexOf('/') + 1) + "ready";
            if (servedRuntime && ("GET " + readyRoute + " HTTP/1.1").equals(first)) {
                out.write("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".getBytes(StandardCharsets.US_ASCII));
                out.flush();
                bootstrapReady = true;
                return;
            }
            if (first == null || !first.equals("GET " + route + " HTTP/1.1")) {
                out.write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".getBytes(StandardCharsets.US_ASCII));
                return;
            }
            out.write("HTTP/1.1 200 OK\r\nContent-Type: application/gzip\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".getBytes(StandardCharsets.US_ASCII));
            try (InputStream payload = getAssets().open("runtime.tar.gz")) {
                byte[] buffer = new byte[65536];
                int n;
                while ((n = payload.read(buffer)) != -1) out.write(buffer, 0, n);
            }
            out.flush();
            servedRuntime = true;
        } catch (Exception ignored) { /* curl can retry an interrupted transfer */ }
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) { return START_NOT_STICKY; }
    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public void onDestroy() {
        runtimeUrl = null;
        servedRuntime = false;
        bootstrapReady = false;
        handler.removeCallbacksAndMessages(null);
        try { if (listener != null) listener.close(); } catch (Exception ignored) { }
        clients.shutdownNow();
        stopForeground(true);
        super.onDestroy();
    }
}
