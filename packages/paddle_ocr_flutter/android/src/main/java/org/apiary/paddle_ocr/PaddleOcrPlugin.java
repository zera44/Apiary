package org.apiary.paddle_ocr;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.ExifInterface;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import ai.onnxruntime.OnnxTensor;
import ai.onnxruntime.OrtEnvironment;
import ai.onnxruntime.OrtSession;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Офлайн-розпізнавання тексту чека (PaddleOCR PP-OCR, ONNX Runtime) для «Моя пасіка».
 *
 * Канал "paddle_ocr_flutter":
 *  - ready: чи є моделі в застосунку (assets/ocr/det.onnx, rec.onnx, dict.txt);
 *  - recognize {path}: {lines: [рядки тексту зверху вниз], ms, rotation, conf}.
 * Усю логіку (детекція рядків, вирізання, читання, збирання) див. OcrPipeline;
 * тут лише читання фото, запуск моделей і міст до Dart.
 */
public class PaddleOcrPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private static final String DET = "assets/ocr/det.onnx", REC = "assets/ocr/rec.onnx", DICT = "assets/ocr/dict.txt";
    /** Більшу сторону фото зменшуємо до цього (пам'ять): чек 4800 пікселів завдовжки ще читається добре. */
    private static final int MAX_SIDE = 4800;

    private MethodChannel channel;
    private Context context;
    private FlutterPlugin.FlutterAssets assets;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());

    private OrtEnvironment env;
    private OrtSession det, rec;
    private String detIn, recIn;
    private String[] chars;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding b) {
        context = b.getApplicationContext();
        assets = b.getFlutterAssets();
        channel = new MethodChannel(b.getBinaryMessenger(), "paddle_ocr_flutter");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding b) {
        channel.setMethodCallHandler(null);
        worker.execute(this::close);
    }

    private synchronized void close() {
        try { if (det != null) det.close(); } catch (Exception ignored) {}
        try { if (rec != null) rec.close(); } catch (Exception ignored) {}
        det = null;
        rec = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "ready":
                worker.execute(() -> {
                    boolean ok;
                    try { open(DET).close(); open(REC).close(); open(DICT).close(); ok = true; } catch (Exception e) { ok = false; }
                    final boolean r = ok;
                    main.post(() -> result.success(r));
                });
                break;
            case "recognize": {
                final String path = call.argument("path");
                worker.execute(() -> {
                    try {
                        final Map<String, Object> r = recognize(path);
                        main.post(() -> result.success(r));
                    } catch (final Throwable e) {
                        main.post(() -> result.error("ocr", String.valueOf(e), null));
                    }
                });
                break;
            }
            default:
                result.notImplemented();
        }
    }

    private InputStream open(String subpath) throws Exception {
        return context.getAssets().open(assets.getAssetFilePathBySubpath(subpath));
    }

    private byte[] bytes(String subpath) throws Exception {
        try (InputStream in = open(subpath)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream(1 << 20);
            byte[] buf = new byte[1 << 16];
            for (int n; (n = in.read(buf)) > 0; ) out.write(buf, 0, n);
            return out.toByteArray();
        }
    }

    private synchronized void load() throws Exception {
        if (det != null && rec != null && chars != null) return;
        env = OrtEnvironment.getEnvironment();
        OrtSession.SessionOptions o = new OrtSession.SessionOptions();
        o.setIntraOpNumThreads(Math.max(2, Math.min(4, Runtime.getRuntime().availableProcessors())));
        det = env.createSession(bytes(DET), o);
        rec = env.createSession(bytes(REC), o);
        detIn = det.getInputNames().iterator().next();
        recIn = rec.getInputNames().iterator().next();
        // словник: порядок символів моделі = ['blank'] + рядки dict.txt + [' ']
        String[] lines = new String(bytes(DICT), "UTF-8").split("\n", -1);
        int n = lines.length;
        if (n > 0 && lines[n - 1].isEmpty()) n--;
        chars = new String[n + 2];
        chars[0] = "";
        for (int i = 0; i < n; i++) chars[i + 1] = lines[i];
        chars[n + 1] = " ";
    }

    /** Фото -> сірі пікселі з урахуванням повороту EXIF; зображення зменшується при читанні, якщо воно завелике. */
    private Object[] readGray(String path) throws Exception {
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(path, o);
        int sample = 1;
        while (Math.max(o.outWidth, o.outHeight) / sample > MAX_SIDE) sample *= 2;
        BitmapFactory.Options d = new BitmapFactory.Options();
        d.inSampleSize = sample;
        Bitmap bmp = BitmapFactory.decodeFile(path, d);
        if (bmp == null) throw new IllegalArgumentException("не вдалося прочитати фото");
        int w = bmp.getWidth(), h = bmp.getHeight();
        int[] px = new int[w * h];
        bmp.getPixels(px, 0, w, 0, 0, w, h);
        bmp.recycle();
        byte[] g = Img.bestGray(px, px.length);
        int orient = ExifInterface.ORIENTATION_NORMAL;
        try { orient = new ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL); } catch (Exception ignored) {}
        if (orient == ExifInterface.ORIENTATION_ROTATE_90) { g = Img.rotate90cw(g, w, h); int t = w; w = h; h = t; }
        else if (orient == ExifInterface.ORIENTATION_ROTATE_180) { g = Img.rotate180(g, w, h); }
        else if (orient == ExifInterface.ORIENTATION_ROTATE_270) { g = Img.rotate180(Img.rotate90cw(g, w, h), h, w); int t = w; w = h; h = t; }
        return new Object[] {g, w, h};
    }

    private Map<String, Object> recognize(String path) throws Exception {
        long t0 = System.currentTimeMillis();
        load();
        Object[] im = readGray(path);
        OcrPipeline.Runner runner = new OcrPipeline.Runner() {
            @Override
            public float[] det(float[] chw, int h, int w) throws Exception {
                try (OnnxTensor in = OnnxTensor.createTensor(env, FloatBuffer.wrap(chw), new long[] {1, 3, h, w});
                     OrtSession.Result r = det.run(Collections.singletonMap(detIn, in))) {
                    FloatBuffer fb = ((OnnxTensor) r.get(0)).getFloatBuffer();
                    float[] o = new float[fb.remaining()];
                    fb.get(o);
                    return o;
                }
            }

            @Override
            public float[] rec(float[] nchw, int n, int w, int[] outTC) throws Exception {
                try (OnnxTensor in = OnnxTensor.createTensor(env, FloatBuffer.wrap(nchw), new long[] {n, 3, 48, w});
                     OrtSession.Result r = rec.run(Collections.singletonMap(recIn, in))) {
                    OnnxTensor t = (OnnxTensor) r.get(0);
                    long[] shape = t.getInfo().getShape();
                    outTC[0] = (int) shape[1];
                    outTC[1] = (int) shape[2];
                    FloatBuffer fb = t.getFloatBuffer();
                    float[] o = new float[fb.remaining()];
                    fb.get(o);
                    return o;
                }
            }
        };
        OcrPipeline.Result res = OcrPipeline.run((byte[]) im[0], (Integer) im[1], (Integer) im[2], runner, chars);
        Map<String, Object> out = new HashMap<>();
        out.put("lines", new ArrayList<>(res.lines));
        out.put("rotation", res.rotation);
        out.put("conf", (double) res.meanConf);
        out.put("ms", (int) (System.currentTimeMillis() - t0));
        return out;
    }
}
