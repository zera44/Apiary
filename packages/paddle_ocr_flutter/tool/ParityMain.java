import java.io.*;
import java.lang.reflect.*;
import java.nio.*;
import java.nio.file.*;
import java.util.*;
import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;

/** Перевірка Java-логіки плагіна на ПК: моделі виконує Python (ort_runner.py), решту рахує справжній код плагіна.
 *  java -cp <classes> ParityMain det.onnx rec.onnx dict.txt image... */
public class ParityMain {
    static String det, rec, runner;

    static float[] run(String model, float[] in, int[] shp, int[] outShape) throws Exception {
        Path tin = Files.createTempFile("in", ".bin"), tout = Files.createTempFile("out", ".bin");
        ByteBuffer bb = ByteBuffer.allocate(in.length * 4).order(ByteOrder.LITTLE_ENDIAN);
        bb.asFloatBuffer().put(in);
        Files.write(tin, bb.array());
        Process p = new ProcessBuilder("python3", "-I", runner, model, tin.toString(), tout.toString(),
                "" + shp[0], "" + shp[1], "" + shp[2], "" + shp[3]).redirectErrorStream(true).start();
        String log = new String(p.getInputStream().readAllBytes());
        if (p.waitFor() != 0) throw new RuntimeException(log);
        ByteBuffer ob = ByteBuffer.wrap(Files.readAllBytes(tout)).order(ByteOrder.LITTLE_ENDIAN);
        int nd = ob.getInt();
        int total = 1;
        for (int i = 0; i < nd; i++) { int d = ob.getInt(); if (outShape != null && i < outShape.length) outShape[i] = d; total *= d; }
        float[] o = new float[total];
        ob.asFloatBuffer().get(o);
        Files.delete(tin); Files.delete(tout);
        return o;
    }

    public static void main(String[] a) throws Exception {
        det = a[0]; rec = a[1];
        runner = Paths.get("tool/ort_runner.py").toAbsolutePath().toString();
        List<String> ch = new ArrayList<>(Files.readAllLines(Paths.get(a[2])));
        ch.add(0, "<blank>"); ch.add(" ");
        String[] chars = ch.toArray(new String[0]);
        Class<?> pc = Class.forName("org.apiary.paddle_ocr.OcrPipeline");
        Class<?> rc = Class.forName("org.apiary.paddle_ocr.OcrPipeline$Runner");
        Class<?> ic = Class.forName("org.apiary.paddle_ocr.Img");
        Method best = ic.getDeclaredMethod("bestGray", int[].class, int.class); best.setAccessible(true);
        Method runM = pc.getDeclaredMethod("run", byte[].class, int.class, int.class, rc, String[].class); runM.setAccessible(true);
        Object runner = Proxy.newProxyInstance(rc.getClassLoader(), new Class<?>[] {rc}, (pr, m, args) -> {
            if (m.getName().equals("det")) {
                float[] t = (float[]) args[0]; int h = (Integer) args[1], w = (Integer) args[2];
                return run(det, t, new int[] {1, 3, h, w}, null);
            }
            float[] t = (float[]) args[0]; int n = (Integer) args[1], w = (Integer) args[2]; int[] tc = (int[]) args[3];
            int[] os = new int[3];
            float[] o = run(rec, t, new int[] {n, 3, 48, w}, os);
            tc[0] = os[1]; tc[1] = os[2];
            return o;
        });
        for (int i = 3; i < a.length; i++) {
            BufferedImage im = ImageIO.read(new File(a[i]));
            int w = im.getWidth(), h = im.getHeight();
            if (Math.max(w, h) > 2400) { // як телефон: фото зменшується при читанні
                double s = 2400.0 / Math.max(w, h);
                BufferedImage sm = new BufferedImage((int) (w * s), (int) (h * s), BufferedImage.TYPE_INT_RGB);
                sm.getGraphics().drawImage(im.getScaledInstance(sm.getWidth(), sm.getHeight(), java.awt.Image.SCALE_AREA_AVERAGING), 0, 0, null);
                im = sm; w = im.getWidth(); h = im.getHeight();
            }
            int[] px = im.getRGB(0, 0, w, h, null, 0, w);
            byte[] g = (byte[]) best.invoke(null, px, px.length);
            long t0 = System.currentTimeMillis();
            Object res = runM.invoke(null, g, w, h, runner, chars);
            Field lf = res.getClass().getDeclaredField("lines"); lf.setAccessible(true);
            Field rf = res.getClass().getDeclaredField("rotation"); rf.setAccessible(true);
            Field cf = res.getClass().getDeclaredField("meanConf"); cf.setAccessible(true);
            System.out.println("== " + a[i] + " " + w + "x" + h + " rot=" + rf.get(res) + " conf=" + cf.get(res) + " " + (System.currentTimeMillis() - t0) + "ms");
            for (Object l : (List<?>) lf.get(res)) System.out.println("  " + l);
            if (System.getenv("BOXES") != null) {
                Field rw = res.getClass().getDeclaredField("rows"); rw.setAccessible(true);
                for (Object r : (List<?>) rw.get(res)) {
                    Field bf = r.getClass().getDeclaredField("box"); bf.setAccessible(true);
                    Field tf = r.getClass().getDeclaredField("text"); tf.setAccessible(true);
                    Object b = bf.get(r);
                    Field fx = b.getClass().getDeclaredField("x"); fx.setAccessible(true);
                    Field fy = b.getClass().getDeclaredField("y"); fy.setAccessible(true);
                    double[] bx = (double[]) fx.get(b), by = (double[]) fy.get(b);
                    System.out.printf("  BOX %.0f,%.0f %.0f,%.0f %.0f,%.0f %.0f,%.0f  %s%n", bx[0], by[0], bx[1], by[1], bx[2], by[2], bx[3], by[3], tf.get(r));
                }
            }
        }
    }
}
