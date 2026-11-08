import ai.onnxruntime.*;
import java.io.*;
import java.lang.reflect.*;
import java.nio.FloatBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/** Перевірка розпізнавача для нечіткої розмітки (OcrV2 + еталон дочитування OcrRecover) на ПК: справжній код плагіна, моделі - ONNX Runtime для Java.
 *  Фото подаються як PPM (P6, RGB) - їх готує tool/to_ppm.py тим самим декодером, що й курсова (cv2).
 *  java -cp <classes>:onnxruntime.jar OcrV2Main det.onnx rec.onnx dict.txt out.csv фото.ppm... */
public class OcrV2Main {
    static volatile long detNs, recNs;
    static int[] readPpm(String path, int[] wh) throws IOException {
        byte[] all = Files.readAllBytes(Paths.get(path));
        int pos = 0, field = 0;
        int[] v = new int[3];
        String magic = null;
        StringBuilder tok = new StringBuilder();
        while (field < 4) {
            char c = (char) (all[pos++] & 255);
            if (c == '#') { while (all[pos++] != '\n') ; continue; }
            if (Character.isWhitespace(c)) {
                if (tok.length() > 0) {
                    if (field == 0) magic = tok.toString(); else v[field - 1] = Integer.parseInt(tok.toString());
                    field++;
                    tok.setLength(0);
                }
                continue;
            }
            tok.append(c);
        }
        if (!"P6".equals(magic)) throw new IOException("not P6");
        int w = v[0], h = v[1];
        int[] px = new int[w * h];
        for (int i = 0; i < w * h; i++) {
            int r = all[pos++] & 255, g = all[pos++] & 255, b = all[pos++] & 255;
            px[i] = 0xff000000 | (r << 16) | (g << 8) | b;
        }
        wh[0] = w; wh[1] = h;
        return px;
    }

    static String q(String s) {
        if (s.contains(",") || s.contains("\"") || s.contains("\n")) return "\"" + s.replace("\"", "\"\"") + "\"";
        return s;
    }

    public static void main(String[] a) throws Exception {
        OrtEnvironment env = OrtEnvironment.getEnvironment();
        OrtSession.SessionOptions so = new OrtSession.SessionOptions();
        OrtSession.SessionOptions so2 = new OrtSession.SessionOptions(); // читач: потоки ORT на виклик (THREADS), решта - паралельні виклики
        if (System.getenv("THREADS") != null) so2.setIntraOpNumThreads(Integer.parseInt(System.getenv("THREADS")));
        OrtSession det = env.createSession(a[0], so), rec = env.createSession(a[1], so2);
        String detIn = det.getInputNames().iterator().next(), recIn = rec.getInputNames().iterator().next();
        List<String> ch = new ArrayList<>(Files.readAllLines(Paths.get(a[2]), StandardCharsets.UTF_8));
        ch.add(0, "<blank>");
        ch.add(" ");
        String[] chars = ch.toArray(new String[0]);
        Class<?> rc = Class.forName("org.apiary.paddle_ocr.OcrPipeline$Runner");
        Object runner = Proxy.newProxyInstance(rc.getClassLoader(), new Class<?>[] {rc}, (pr, m, args) -> {
            float[] t = (float[]) args[0];
            long t0 = System.nanoTime();
            try {
            if (m.getName().equals("det")) {
                int h = (Integer) args[1], w = (Integer) args[2];
                try (OnnxTensor in = OnnxTensor.createTensor(env, FloatBuffer.wrap(t), new long[] {1, 3, h, w});
                     OrtSession.Result r = det.run(Collections.singletonMap(detIn, in))) {
                    FloatBuffer fb = ((OnnxTensor) r.get(0)).getFloatBuffer();
                    float[] o = new float[fb.remaining()];
                    fb.get(o);
                    return o;
                }
            }
            int n = (Integer) args[1], w = (Integer) args[2];
            int[] tc = (int[]) args[3];
            try (OnnxTensor in = OnnxTensor.createTensor(env, FloatBuffer.wrap(t), new long[] {n, 3, 48, w});
                 OrtSession.Result r = rec.run(Collections.singletonMap(recIn, in))) {
                OnnxTensor ot = (OnnxTensor) r.get(0);
                long[] shape = ot.getInfo().getShape();
                tc[0] = (int) shape[1];
                tc[1] = (int) shape[2];
                FloatBuffer fb = ot.getFloatBuffer();
                float[] o = new float[fb.remaining()];
                fb.get(o);
                return o;
            }
            } finally { if (m.getName().equals("det")) detNs += System.nanoTime() - t0; else recNs += System.nanoTime() - t0; }
        });
        Class<?> oc = Class.forName("org.apiary.paddle_ocr.OcrV2");
        Class<?> gc = Class.forName("org.apiary.paddle_ocr.OcrV2$Gray");
        Class<?> rdc = Class.forName("org.apiary.paddle_ocr.OcrV2$Reader");
        Class<?> ic = Class.forName("org.apiary.paddle_ocr.Img");
        Method best = ic.getDeclaredMethod("bestGrayPy", int[].class, int.class);
        best.setAccessible(true);
        Constructor<?> gcons = gc.getDeclaredConstructor(byte[].class, int.class, int.class);
        gcons.setAccessible(true);
        Constructor<?> rcons = rdc.getDeclaredConstructor(rc, String[].class);
        rcons.setAccessible(true);
        Class<?> recov = Class.forName("org.apiary.paddle_ocr.OcrRecover"); // еталон: tool/oracle/OcrRecover.java
        Method fxBegin = recov.getDeclaredMethod("fxBegin", String.class), fxEnd = recov.getDeclaredMethod("fxEnd");
        fxBegin.setAccessible(true);
        fxEnd.setAccessible(true);
        String fxDir = System.getenv("FX_DIR"); // запис читань моделі для перевірки Dart-версії дочитування
        Method full = recov.getDeclaredMethod("recognize", gc, rdc, String.class);
        full.setAccessible(true);
        try (PrintWriter out = new PrintWriter(new OutputStreamWriter(new FileOutputStream(a[3]), StandardCharsets.UTF_8))) {
            out.println("receipt,box_id,line_id,text,conf,x,y,w,h,x_left,x_right,img_w,img_h,rotation,receipt_conf,angle,recovered,hand");
            for (int i = 4; i < a.length; i++) {
                int[] wh = new int[2];
                int[] px = readPpm(a[i], wh);
                byte[] g = (byte[]) best.invoke(null, px, px.length);
                Object gray = gcons.newInstance(g, wh[0], wh[1]);
                Object rd = rcons.newInstance(runner, chars);
                String name = Paths.get(a[i]).getFileName().toString().replace(".ppm", "");
                long t0 = System.currentTimeMillis();
                if (fxDir != null) fxBegin.invoke(null, fxDir + "/" + name + ".fx");
                Object res = full.invoke(null, gray, rd, System.getenv("NO_RECOVER") != null ? "ocr" : "all");
                if (fxDir != null) fxEnd.invoke(null);
                long ms = System.currentTimeMillis() - t0;
                Field ff = res.getClass().getDeclaredField("frags");
                ff.setAccessible(true);
                Field rotF = res.getClass().getDeclaredField("rotation");
                rotF.setAccessible(true);
                Field rcF = rdc.getDeclaredField("recCalls");
                rcF.setAccessible(true);
                Field dcF = rdc.getDeclaredField("detCalls");
                dcF.setAccessible(true);
                List<?> frags = (List<?>) ff.get(res);
                System.err.println(name + " rot=" + rotF.get(res) + " frags=" + frags.size() + " det=" + dcF.get(rd) + " rec=" + rcF.get(rd) + " " + ms + "ms det_ms=" + detNs / 1000000 + " rec_ms=" + recNs / 1000000);
                detNs = 0; recNs = 0;
                for (Object f : frags) {
                    Class<?> fc = f.getClass();
                    java.util.function.Function<String, Object> get = n -> {
                        try { Field x = fc.getDeclaredField(n); x.setAccessible(true); return x.get(f); } catch (Exception e) { throw new RuntimeException(e); }
                    };
                    Object hand = get.apply("hand");
                    out.println(String.join(",", "rec_" + name + ".jpg", "" + get.apply("boxId"), "0", q((String) get.apply("text")),
                            "" + get.apply("conf"), "" + get.apply("x"), "" + get.apply("y"), "" + get.apply("w"), "" + get.apply("h"),
                            "" + get.apply("xLeft"), "" + get.apply("xRight"), "" + get.apply("imgW"), "" + get.apply("imgH"),
                            "" + get.apply("rotation"), "" + get.apply("receiptConf"), "" + get.apply("angle"),
                            ((Boolean) get.apply("recovered")) ? "1" : "", hand == null ? "" : (String) hand));
                }
                out.flush();
            }
        }
    }
}
