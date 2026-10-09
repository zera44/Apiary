package org.apiary.vosk_flutter;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

import org.vosk.Model;
import org.vosk.Recognizer;
import org.vosk.android.RecognitionListener;
import org.vosk.android.SpeechService;

/**
 * Офлайн-розпізнавання мови Vosk для «Моя пасіка».
 *
 * Методи (канал "vosk_flutter"):
 *  - ready {version}: чи модель уже розпакована на телефоні;
 *  - init {zip, version}: розпакувати скачаний архів моделі (лише першого
 *    разу, потім архів видаляється) і завантажити модель;
 *  - permission: чи є дозвіл на мікрофон, за потреби - запитати;
 *  - start: слухати мікрофон; stop: зупинити (прийде остаточний текст);
 *    cancel: зупинити без результату.
 * Події (канал "vosk_flutter/events"): {type: partial|result|final|error, text}.
 */
public class VoskFlutterPlugin implements FlutterPlugin, ActivityAware,
        MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
        PluginRegistry.RequestPermissionsResultListener {

    private static final int PERMISSION_CODE = 47301;
    private static final float SAMPLE_RATE = 16000f;

    private MethodChannel channel;
    private EventChannel events;
    private EventChannel.EventSink sink;
    private Context context;
    private Activity activity;
    private ActivityPluginBinding activityBinding;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    private Model model;
    private String modelVersion;
    private Session speech;
    private MethodChannel.Result pendingPermission;

    // ------------------------------------------------------------ життєвий цикл

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "vosk_flutter");
        channel.setMethodCallHandler(this);
        events = new EventChannel(binding.getBinaryMessenger(), "vosk_flutter/events");
        events.setStreamHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        stopSpeech(true);
        channel.setMethodCallHandler(null);
        events.setStreamHandler(null);
        if (model != null) {
            model.close();
            model = null;
        }
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        activity = binding.getActivity();
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        if (activityBinding != null) activityBinding.removeRequestPermissionsResultListener(this);
        activityBinding = null;
        activity = null;
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        sink = events;
    }

    @Override
    public void onCancel(Object arguments) {
        sink = null;
    }

    // ------------------------------------------------------------------ методи

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "init":
                init(call.argument("zip"), call.argument("version"), result);
                break;
            case "ready": {
                String v = call.argument("version");
                result.success(v != null && new File(modelRoot(v), ".ok").exists());
                break;
            }
            case "permission":
                permission(result);
                break;
            case "start":
                start(result);
                break;
            case "stop":
                if (speech != null) speech.service.stop(); // остаточний текст прийде в onFinalResult
                result.success(true);
                break;
            case "cancel":
                stopSpeech(true);
                result.success(true);
                break;
            default:
                result.notImplemented();
        }
    }

    private File modelRoot(String version) {
        return new File(context.getFilesDir(), "vosk/" + version.replaceAll("[^A-Za-z0-9._-]", "_"));
    }

    /**
     * Завантажити модель [version]. Якщо її ще не розпаковано - розпакувати
     * скачаний архів [zip] (після цього архів видаляється).
     */
    private void init(String zip, String version, MethodChannel.Result result) {
        if (version == null) {
            result.error("ARGS", "version обов'язковий", null);
            return;
        }
        if (model != null && version.equals(modelVersion)) {
            result.success(true);
            return;
        }
        worker.execute(() -> {
            try {
                File dir = unpack(zip, modelRoot(version));
                Model m = new Model(dir.getAbsolutePath());
                main.post(() -> {
                    if (model != null) model.close();
                    model = m;
                    modelVersion = version;
                    result.success(true);
                });
            } catch (Exception e) {
                main.post(() -> result.error("MODEL", String.valueOf(e.getMessage()), null));
            }
        });
    }

    /**
     * Розпакувати zip-модель [zipPath] у [root] (лише першого разу: позначка
     * ".ok" ставиться після повного розпакування). Повертає теку моделі
     * (єдина тека верхнього рівня архіву або сам [root]).
     */
    private File unpack(String zipPath, File root) throws IOException {
        File ok = new File(root, ".ok");
        if (!ok.exists()) {
            if (zipPath == null || !new File(zipPath).isFile()) throw new IOException("NOMODEL");
            deleteTree(root);
            if (!root.mkdirs() && !root.isDirectory()) throw new IOException("не вдалося створити " + root);
            // старі версії моделі більше не потрібні
            File[] old = root.getParentFile().listFiles();
            if (old != null) {
                for (File f : old) {
                    if (!f.equals(root)) deleteTree(f);
                }
            }
            String canonRoot = root.getCanonicalPath() + File.separator;
            byte[] buf = new byte[1 << 16];
            try (InputStream in = new FileInputStream(zipPath);
                 ZipInputStream zip = new ZipInputStream(in)) {
                ZipEntry e;
                while ((e = zip.getNextEntry()) != null) {
                    File out = new File(root, e.getName());
                    // захист від шляхів на кшталт ../
                    if (!out.getCanonicalPath().startsWith(canonRoot)) throw new IOException("поганий шлях у архіві");
                    if (e.isDirectory()) {
                        out.mkdirs();
                        continue;
                    }
                    File parent = out.getParentFile();
                    if (parent != null) parent.mkdirs();
                    try (OutputStream os = new FileOutputStream(out)) {
                        int n;
                        while ((n = zip.read(buf)) > 0) os.write(buf, 0, n);
                    }
                }
            }
            if (!ok.createNewFile() && !ok.exists()) throw new IOException("не вдалося записати позначку");
            //noinspection ResultOfMethodCallIgnored
            new File(zipPath).delete(); // друга копія моделі на телефоні не потрібна
        }
        File[] items = root.listFiles(f -> f.isDirectory());
        File[] all = root.listFiles(f -> !f.getName().equals(".ok"));
        if (items != null && all != null && items.length == 1 && all.length == 1) return items[0];
        return root;
    }

    private static void deleteTree(File f) {
        if (f == null || !f.exists()) return;
        File[] kids = f.listFiles();
        if (kids != null) {
            for (File k : kids) deleteTree(k);
        }
        //noinspection ResultOfMethodCallIgnored
        f.delete();
    }

    private boolean hasPermission() {
        return Build.VERSION.SDK_INT < 23
                || context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
    }

    private void permission(MethodChannel.Result result) {
        if (hasPermission()) {
            result.success(true);
            return;
        }
        if (activity == null || Build.VERSION.SDK_INT < 23) {
            result.success(false);
            return;
        }
        if (pendingPermission != null) pendingPermission.success(false);
        pendingPermission = result;
        activity.requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, PERMISSION_CODE);
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        if (requestCode != PERMISSION_CODE) return false;
        MethodChannel.Result r = pendingPermission;
        pendingPermission = null;
        if (r != null) {
            r.success(grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED);
        }
        return true;
    }

    private void start(MethodChannel.Result result) {
        if (model == null) {
            result.error("MODEL", "модель не завантажено", null);
            return;
        }
        if (!hasPermission()) {
            result.error("PERMISSION", "немає дозволу на мікрофон", null);
            return;
        }
        stopSpeech(true);
        Session s = new Session();
        try {
            Recognizer rec = new Recognizer(model, SAMPLE_RATE);
            s.service = new SpeechService(rec, SAMPLE_RATE);
            speech = s;
            s.service.startListening(s);
            result.success(true);
        } catch (Exception e) {
            stopSpeech(true);
            result.error("START", String.valueOf(e.getMessage()), null);
        }
    }

    private void stopSpeech(boolean cancel) {
        Session s = speech;
        speech = null;
        if (s != null) s.close(cancel);
    }

    /** Один сеанс слухання: події старого сеансу нового не чіпають. */
    private class Session implements RecognitionListener {
        SpeechService service;
        boolean closed;

        void close(boolean cancel) {
            if (closed || service == null) return;
            closed = true;
            if (cancel) service.cancel();
            service.shutdown();
        }

        private void emit(String type, String text) {
            main.post(() -> {
                if (speech != this || sink == null) return;
                Map<String, Object> m = new HashMap<>();
                m.put("type", type);
                m.put("text", text);
                sink.success(m);
            });
        }

        private void finish(String type, String text, boolean cancel) {
            main.post(() -> {
                if (speech == this) {
                    if (sink != null) {
                        Map<String, Object> m = new HashMap<>();
                        m.put("type", type);
                        m.put("text", text);
                        sink.success(m);
                    }
                    speech = null;
                }
                close(cancel);
            });
        }

        @Override
        public void onPartialResult(String hypothesis) {
            emit("partial", hypothesis);
        }

        @Override
        public void onResult(String hypothesis) {
            emit("result", hypothesis);
        }

        @Override
        public void onFinalResult(String hypothesis) {
            finish("final", hypothesis, false);
        }

        @Override
        public void onError(Exception exception) {
            finish("error", String.valueOf(exception.getMessage()), true);
        }

        @Override
        public void onTimeout() {
            finish("final", "{\"text\": \"\"}", true);
        }
    }
}
