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
 *  - recognize {path}: {lines: [рядки тексту зверху вниз], ms, rotation, conf};
 *  - ocrBegin {path}: сіре зображення, поворот і детектор (OcrV2): {session, frags: [{box_id, text, conf, x, y, w, h,
 *    x_left, x_right, angle, img_w, img_h, recovered, hand}], rotation, conf, ms}. Дочитування (правила) - у Dart
 *    (lib/logic/fz2/recover.dart), а тут лише те, що потребує моделей і зображення:
 *  - ocrRead {session, angle, reqs: [{x1, x2, y1, y2, st: [...]}]}: [{text, conf}] - читання рамок (паралельно);
 *  - ocrDegen {session, angle, frag}: тісна рамка за чорнилом для виродженого фрагмента -> змінений фрагмент;
 *  - ocrHand {session, frags}: рукописні рядки бланка «Товарний чек» -> фрагменти;
 *  - ocrEnd {session, image?}: якщо дано image - туди записується JPEG того сірого зображення, яке читалося
 *    (координати фрагментів - у його кадрі, повернутому на -angle); сесія закривається.
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
    private OrtSession det, rec, recSeq;
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
        try { if (recSeq != null) recSeq.close(); } catch (Exception ignored) {}
        det = null;
        rec = null;
        recSeq = null;
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
            case "ocrBegin":
            case "ocrRead":
            case "ocrDegen":
            case "ocrHand":
            case "ocrEnd": {
                worker.execute(() -> {
                    try {
                        final Object r = session(call);
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
        int cores = Math.max(2, Math.min(4, Runtime.getRuntime().availableProcessors()));
        // детектор - один великий виклик: потоки на виклик; читач - багато малих викликів, які OcrV2.Reader
        // веде паралельно, тож кожному потрібен один потік (інакше ядра воюють між собою)
        OrtSession.SessionOptions o = new OrtSession.SessionOptions();
        o.setIntraOpNumThreads(cores);
        OrtSession.SessionOptions o2 = new OrtSession.SessionOptions();
        o2.setIntraOpNumThreads(1);
        det = env.createSession(bytes(DET), o);
        rec = env.createSession(bytes(REC), o2);
        recSeq = env.createSession(bytes(REC), o); // для послідовного читання (екран складу): потоки на виклик
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
    private Object[] readGray(String path) throws Exception { return readGray(path, false); }

    private Object[] readGray(String path, boolean py) throws Exception {
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
        byte[] g = py ? Img.bestGrayPy(px, px.length) : Img.bestGray(px, px.length);
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
        OcrPipeline.Result res = OcrPipeline.run((byte[]) im[0], (Integer) im[1], (Integer) im[2], runner(recSeq), chars);
        Map<String, Object> out = new HashMap<>();
        out.put("lines", new ArrayList<>(res.lines));
        List<List<String>> alt = new ArrayList<>();
        for (List<String> l : res.altLines) alt.add(new ArrayList<>(l));
        out.put("altLines", alt);
        out.put("rotation", res.rotation);
        out.put("conf", (double) res.meanConf);
        out.put("ms", (int) (System.currentTimeMillis() - t0));
        return out;
    }

    /** Відкрита сесія: сіре зображення, яке читається (повернуте прямо), і читач. Одна на раз. */
    private static final class Session {
        final String id;
        final OcrV2.Gray g;
        final OcrV2.Reader rd;

        Session(String id, OcrV2.Gray g, OcrV2.Reader rd) { this.id = id; this.g = g; this.rd = rd; }
    }

    private Session current;
    private int sessionSeq;

    private synchronized Session need(MethodCall call) {
        String id = call.argument("session");
        if (current == null || !current.id.equals(id)) throw new IllegalStateException("сесію розпізнавання закрито");
        return current;
    }

    private Object session(MethodCall call) throws Exception {
        switch (call.method) {
            case "ocrBegin": return begin(call.argument("path"));
            case "ocrRead": return readBoxes(need(call), call);
            case "ocrDegen": {
                Session s = need(call);
                double a = ((Number) call.argument("angle")).doubleValue();
                OcrV2.Frag f = fragOf(call.argument("frag"));
                OcrPrim.degenBox(f, s.g, a);
                return fragMap(f);
            }
            case "ocrHand": {
                Session s = need(call);
                List<OcrV2.Frag> fr = new ArrayList<>();
                for (Map<String, Object> m : call.<List<Map<String, Object>>>argument("frags")) fr.add(fragOf(m));
                List<Map<String, Object>> out = new ArrayList<>();
                if (!fr.isEmpty()) for (OcrV2.Frag f : OcrHand.handRows(fr, s.g, s.rd)) out.add(fragMap(f));
                return out;
            }
            default: { // ocrEnd
                Session s = need(call);
                String image = call.argument("image");
                synchronized (this) { current = null; }
                if (image != null) saveGray(s.g, image);
                return true;
            }
        }
    }

    private Map<String, Object> begin(String path) throws Exception {
        long t0 = System.currentTimeMillis();
        load();
        Object[] im = readGray(path, true);
        OcrV2.Gray g0 = new OcrV2.Gray((byte[]) im[0], (Integer) im[1], (Integer) im[2]);
        OcrV2.Reader rd = new OcrV2.Reader(runner(rec), chars);
        OcrV2.Result res = OcrV2.run(g0, rd);
        Session s;
        synchronized (this) {
            s = new Session("s" + (++sessionSeq), res.g != null ? res.g : g0, rd);
            current = s;
        }
        List<Map<String, Object>> frags = new ArrayList<>();
        for (OcrV2.Frag f : res.frags) frags.add(fragMap(f));
        Map<String, Object> out = new HashMap<>();
        out.put("session", s.id);
        out.put("frags", frags);
        out.put("rotation", res.rotation);
        out.put("conf", res.conf);
        out.put("ms", (int) (System.currentTimeMillis() - t0));
        return out;
    }

    private List<Map<String, Object>> readBoxes(final Session s, MethodCall call) throws Exception {
        final double a = ((Number) call.argument("angle")).doubleValue();
        List<java.util.concurrent.Callable<Map<String, Object>>> jobs = new ArrayList<>();
        for (final Map<String, Object> q : call.<List<Map<String, Object>>>argument("reqs")) {
            final OcrV2.Quad box = OcrPrim.quad(a, num(q, "x1"), num(q, "x2"), num(q, "y1"), num(q, "y2"));
            List<?> st = (List<?>) q.get("st");
            final double[] stretch = new double[st.size()];
            for (int i = 0; i < stretch.length; i++) stretch[i] = ((Number) st.get(i)).doubleValue();
            jobs.add(() -> {
                OcrV2.Read r = OcrV2.read(s.g, box, s.rd, stretch);
                Map<String, Object> m = new HashMap<>();
                m.put("text", r.text);
                m.put("conf", r.conf);
                return m;
            });
        }
        return s.rd.parallel(jobs);
    }

    private static double num(Map<String, Object> m, String k) { return ((Number) m.get(k)).doubleValue(); }

    private static Map<String, Object> fragMap(OcrV2.Frag f) {
        Map<String, Object> m = new HashMap<>();
        m.put("box_id", f.boxId);
        m.put("text", f.text);
        m.put("conf", f.conf);
        m.put("x", f.x);
        m.put("y", f.y);
        m.put("w", f.w);
        m.put("h", f.h);
        m.put("x_left", f.xLeft);
        m.put("x_right", f.xRight);
        m.put("angle", f.angle);
        m.put("skew", f.skew);
        m.put("img_w", f.imgW);
        m.put("img_h", f.imgH);
        m.put("recovered", f.recovered);
        m.put("hand", f.hand);
        return m;
    }

    private static OcrV2.Frag fragOf(Map<String, Object> m) {
        OcrV2.Frag f = new OcrV2.Frag();
        f.boxId = ((Number) m.get("box_id")).intValue();
        f.text = (String) m.get("text");
        f.conf = num(m, "conf");
        f.x = num(m, "x");
        f.y = num(m, "y");
        f.w = num(m, "w");
        f.h = num(m, "h");
        f.xLeft = num(m, "x_left");
        f.xRight = num(m, "x_right");
        f.angle = num(m, "angle");
        f.skew = m.get("skew") instanceof Number ? ((Number) m.get("skew")).doubleValue() : Double.NaN;
        f.imgW = ((Number) m.get("img_w")).intValue();
        f.imgH = ((Number) m.get("img_h")).intValue();
        f.recovered = Boolean.TRUE.equals(m.get("recovered"));
        f.hand = (String) m.get("hand");
        return f;
    }

    private static void saveGray(OcrV2.Gray g, String path) throws Exception {
        int[] px = new int[g.w * g.h];
        for (int i = 0; i < px.length; i++) {
            int v = g.p[i] & 255;
            px[i] = 0xff000000 | (v << 16) | (v << 8) | v;
        }
        Bitmap bmp = Bitmap.createBitmap(px, g.w, g.h, Bitmap.Config.ARGB_8888);
        try (java.io.FileOutputStream out = new java.io.FileOutputStream(path)) {
            bmp.compress(Bitmap.CompressFormat.JPEG, 85, out);
        } finally {
            bmp.recycle();
        }
    }

    private OcrPipeline.Runner runner(final OrtSession recSession) {
        return new OcrPipeline.Runner() {
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
                     OrtSession.Result r = recSession.run(Collections.singletonMap(recIn, in))) {
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
    }
}
