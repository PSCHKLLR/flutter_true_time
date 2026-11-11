package dev.pschkllr.flutter_true_time;

import android.content.Context;
import android.provider.Settings;
import android.util.AtomicFile;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Only bootstrap metadata crosses the channel; hot-path clock reads use FFI. */
public final class FlutterTrueTimePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private static final Object INSTALL_LOCK = new Object();
    private MethodChannel channel;
    private Context context;
    @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "dev.pschkllr.flutter_true_time/epoch");
        channel.setMethodCallHandler(this);
    }
    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        if (!"getBootEpoch".equals(call.method)) { result.notImplemented(); return; }
        String namespace = call.argument("namespace");
        if (namespace == null || !namespace.matches("[a-zA-Z0-9_.-]{3,128}")) {
            result.error("invalidNamespace", "Use an application-specific namespace", null); return;
        }
        try {
            int count = Settings.Global.getInt(context.getContentResolver(), Settings.Global.BOOT_COUNT);
            if (count < 0) { result.success(null); return; }
            String installation;
            synchronized (INSTALL_LOCK) {
                AtomicFile marker = new AtomicFile(new File(context.getNoBackupFilesDir(), "flutter_true_time." + namespace + ".installation"));
                try {
                    installation = new String(marker.readFully(), StandardCharsets.UTF_8);
                    UUID.fromString(installation);
                } catch (Exception invalidOrMissing) {
                    installation = UUID.randomUUID().toString();
                    FileOutputStream stream = null;
                    try {
                        stream = marker.startWrite();
                        stream.write(installation.getBytes(StandardCharsets.UTF_8));
                        marker.finishWrite(stream);
                    } catch (Exception writeFailed) {
                        if (stream != null) marker.failWrite(stream);
                        throw writeFailed;
                    }
                }
            }
            Map<String, Object> epoch = new HashMap<>();
            epoch.put("bootId", "android-boot-" + count);
            epoch.put("installationScope", installation);
            result.success(epoch);
        } catch (Exception unavailable) {
            // Permission/storage/OS limitations must require a fresh network sync.
            result.success(null);
        }
    }
    @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null); channel = null; context = null;
    }
}
