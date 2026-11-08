package org.apiary.paddle_ocr;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

/**
 * Розпізнавач чека для нечіткої розмітки (перенесення coursework/fuzzy_v2/ocr.py):
 * детектор DB з ширшими рамками (unclip 2.0 і поздовжній запас), злиття розірваних рамок рядка,
 * дрібний текст - збільшення й детекція смугами, читання з розтягненням, повороти 0/180 (і 90/270 для фото боком).
 * Результат - фрагменти з рамками у системі координат вирівняного фото (як raw*.csv курсової),
 * далі їх дочитує [OcrRecover] і розмічає fz2 у Dart.
 * Логіка без Android і перевіряється на ПК (tool/OcrV2Main.java).
 */
final class OcrV2 {
    private OcrV2() {}

    static final double UNCLIP = 2.0, PAD = 0.3;

    /** Сіре зображення (байт 0..255). */
    static final class Gray {
        final byte[] p;
        final int w, h;

        Gray(byte[] p, int w, int h) { this.p = p; this.w = w; this.h = h; }
    }

    /** Чотирикутник: лівий-верхній, правий-верхній, правий-нижній, лівий-нижній. */
    static final class Quad {
        final double[] x = new double[4], y = new double[4];

        double len(int a, int b) { return Math.hypot(x[a] - x[b], y[a] - y[b]); }

        double minX() { return Math.min(Math.min(x[0], x[1]), Math.min(x[2], x[3])); }

        double maxX() { return Math.max(Math.max(x[0], x[1]), Math.max(x[2], x[3])); }

        double meanY() { return (y[0] + y[1] + y[2] + y[3]) / 4; }

        Quad scaled(double s) {
            Quad q = new Quad();
            for (int i = 0; i < 4; i++) { q.x[i] = x[i] / s; q.y[i] = y[i] / s; }
            return q;
        }

        Quad shiftedY(double dy) {
            Quad q = new Quad();
            for (int i = 0; i < 4; i++) { q.x[i] = x[i]; q.y[i] = y[i] + dy; }
            return q;
        }
    }

    static final class Row {
        final Quad b;
        final String text;
        final double conf;

        Row(Quad b, String text, double conf) { this.b = b; this.text = text; this.conf = conf; }
    }

    /** Прочитаний текст і впевненість. */
    static final class Read {
        final String text;
        final double conf;

        Read(String text, double conf) { this.text = text; this.conf = conf; }
    }

    /** Фрагмент для розмітки (стовпці raw*.csv). */
    static final class Frag {
        int boxId;
        String text;
        double conf, x, y, w, h, xLeft, xRight, angle;
        int imgW, imgH, rotation;
        double receiptConf;
        boolean recovered;
        String hand; // null - друкований

        Frag copy() {
            Frag f = new Frag();
            f.boxId = boxId; f.text = text; f.conf = conf; f.x = x; f.y = y; f.w = w; f.h = h;
            f.xLeft = xLeft; f.xRight = xRight; f.angle = angle; f.imgW = imgW; f.imgH = imgH;
            f.rotation = rotation; f.receiptConf = receiptConf; f.recovered = recovered; f.hand = hand;
            return f;
        }
    }

    static final class Result {
        int rotation;
        double conf;
        Gray g;
        final List<Frag> frags = new ArrayList<>();
    }

    /** Читач рядків: моделі (ONNX Runtime) і словник. */
    static final class Reader {
        final OcrPipeline.Runner run;
        final String[] chars;
        final java.util.concurrent.atomic.AtomicInteger recCalls = new java.util.concurrent.atomic.AtomicInteger();
        final java.util.concurrent.atomic.AtomicInteger detCalls = new java.util.concurrent.atomic.AtomicInteger();

        Reader(OcrPipeline.Runner run, String[] chars) { this.run = run; this.chars = chars; }

        /** Потоки для незалежних читань: один виклик моделі слабо виграє від кількох ядер, а кілька викликів - добре. */
        static final java.util.concurrent.ExecutorService POOL = java.util.concurrent.Executors.newFixedThreadPool(
                Math.max(2, Math.min(4, Runtime.getRuntime().availableProcessors())), r -> {
                    Thread t = new Thread(r, "ocr-read");
                    t.setDaemon(true);
                    return t;
                });

        /** Виконати незалежні читання паралельно; результати - у порядку завдань, тож відповідь та сама, що й послідовна. */
        <T> List<T> parallel(List<java.util.concurrent.Callable<T>> jobs) throws Exception {
            List<T> out = new ArrayList<>(jobs.size());
            if (jobs.size() <= 1) {
                for (java.util.concurrent.Callable<T> j : jobs) out.add(j.call());
                return out;
            }
            List<java.util.concurrent.Future<T>> fs = new ArrayList<>(jobs.size());
            for (java.util.concurrent.Callable<T> j : jobs) fs.add(POOL.submit(j));
            try {
                for (java.util.concurrent.Future<T> f : fs) out.add(f.get());
            } catch (java.util.concurrent.ExecutionException e) {
                for (java.util.concurrent.Future<T> f : fs) f.cancel(true);
                Throwable c = e.getCause();
                throw c instanceof Exception ? (Exception) c : e;
            }
            return out;
        }
    }

    // ------------------------------------------------------------------ зображення

    static int px(Gray g, int x, int y) {
        if (x < 0) x = 0; else if (x >= g.w) x = g.w - 1;
        if (y < 0) y = 0; else if (y >= g.h) y = g.h - 1;
        return g.p[y * g.w + x] & 255;
    }

    static double bilinear(Gray g, double x, double y) {
        int x0 = (int) Math.floor(x), y0 = (int) Math.floor(y);
        double fx = x - x0, fy = y - y0;
        double a = px(g, x0, y0), b = px(g, x0 + 1, y0), c = px(g, x0, y0 + 1), d = px(g, x0 + 1, y0 + 1);
        return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy;
    }

    static byte sat(double v) { return (byte) Math.max(0, Math.min(255, Math.round(v))); }

    /**
     * cv2.resize(INTER_LINEAR) для uint8 бітово точно, як OpenCV на ПК (x86, SIMD): ваги з float у фіксованій
     * точці 11 біт, по вертикалі ((b0*(r0>>4))>>16 + (b1*(r1>>4))>>16 + 2) >> 2.
     */
    static Gray resizeLinear(Gray g, int nw, int nh) {
        int[] xs = new int[nw], xa0 = new int[nw], xa1 = new int[nw];
        linTab(g.w, nw, true, xs, xa0, xa1);
        int[] ys = new int[nh], ya0 = new int[nh], ya1 = new int[nh];
        linTab(g.h, nh, false, ys, ya0, ya1);
        int[][] rows = new int[g.h][];
        byte[] o = new byte[nw * nh];
        for (int y = 0; y < nh; y++) {
            int r0i = Math.min(Math.max(ys[y], 0), g.h - 1), r1i = Math.min(Math.max(ys[y] + 1, 0), g.h - 1);
            int[] r0 = linRow(g, rows, r0i, xs, xa0, xa1), r1 = linRow(g, rows, r1i, xs, xa0, xa1);
            long b0 = ya0[y], b1 = ya1[y];
            for (int x = 0; x < nw; x++) {
                long v = (((b0 * (r0[x] >> 4)) >> 16) + ((b1 * (r1[x] >> 4)) >> 16) + 2) >> 2;
                o[y * nw + x] = (byte) Math.max(0, Math.min(255, v));
            }
        }
        return new Gray(o, nw, nh);
    }

    private static int[] linRow(Gray g, int[][] cache, int y, int[] xs, int[] a0, int[] a1) {
        if (cache[y] != null) return cache[y];
        int[] r = new int[xs.length];
        int base = y * g.w;
        for (int x = 0; x < xs.length; x++) {
            int s0 = xs[x], s1 = Math.min(s0 + 1, g.w - 1);
            r[x] = (g.p[base + s0] & 255) * a0[x] + (g.p[base + s1] & 255) * a1[x];
        }
        cache[y] = r;
        return r;
    }

    /** Таблиця лінійної інтерполяції OpenCV: f у float, по x - притиснута до країв, по y - ні. */
    private static void linTab(int ss, int ds, boolean clampF, int[] idx, int[] a0, int[] a1) {
        double scale = 1.0 / ((double) ds / ss);
        for (int d = 0; d < ds; d++) {
            float f = (float) ((d + 0.5) * scale - 0.5);
            int s = (int) Math.floor(f);
            f -= s;
            if (clampF) {
                if (s < 0) { f = 0; s = 0; }
                if (s + 1 >= ss && s >= ss - 1) { f = 0; s = ss - 1; }
            }
            idx[d] = s;
            a0[d] = (int) Math.rint((1.f - f) * 2048f);
            a1[d] = (int) Math.rint(f * 2048f);
        }
    }

    /** cv2.resize(INTER_AREA) для зменшення: ваги й суми у float, округлення до парного (cvRound), як в OpenCV. */
    static Gray resizeArea(Gray g, int nw, int nh) {
        double scx = 1.0 / ((double) nw / g.w), scy = 1.0 / ((double) nh / g.h);
        int isx = (int) Math.rint(scx), isy = (int) Math.rint(scy);
        byte[] o = new byte[nw * nh];
        if (Math.abs(scx - isx) < 2.220446049250313e-16 && Math.abs(scy - isy) < 2.220446049250313e-16) {
            float k = 1.f / (isx * isy); // ціле зменшення: середнє блоку
            for (int y = 0; y < nh; y++) {
                for (int x = 0; x < nw; x++) {
                    int sum = 0;
                    for (int dy = 0; dy < isy; dy++)
                        for (int dx = 0; dx < isx; dx++) sum += g.p[(y * isy + dy) * g.w + x * isx + dx] & 255;
                    o[y * nw + x] = satF(sum * k);
                }
            }
            return new Gray(o, nw, nh);
        }
        int[][] xt = areaTab(g.w, nw, scx), yt = areaTab(g.h, nh, scy);
        float[] xa = areaAlpha(g.w, nw, scx), ya = areaAlpha(g.h, nh, scy);
        float[] buf = new float[nw], sum = new float[nw];
        int prev = yt[0][0];
        for (int k = 0; k < yt[0].length; k++) {
            int sy = yt[1][k], dy = yt[0][k];
            java.util.Arrays.fill(buf, 0f);
            int row = sy * g.w;
            for (int t = 0; t < xt[0].length; t++) buf[xt[0][t]] += (g.p[row + xt[1][t]] & 255) * xa[t];
            float beta = ya[k];
            if (dy != prev) {
                for (int x = 0; x < nw; x++) { o[prev * nw + x] = satF(sum[x]); sum[x] = beta * buf[x]; }
                prev = dy;
            } else {
                for (int x = 0; x < nw; x++) sum[x] += beta * buf[x];
            }
        }
        for (int x = 0; x < nw; x++) o[prev * nw + x] = satF(sum[x]);
        return new Gray(o, nw, nh);
    }

    static byte satF(float v) { return (byte) Math.max(0, Math.min(255, (int) Math.rint(v))); }

    /** computeResizeAreaTab з OpenCV: [0] - індекс у результаті, [1] - у джерелі. */
    private static int[][] areaTab(int ssize, int dsize, double scale) {
        List<int[]> t = new ArrayList<>();
        areaWalk(ssize, dsize, scale, t, null);
        int[][] r = new int[2][t.size()];
        for (int i = 0; i < t.size(); i++) { r[0][i] = t.get(i)[0]; r[1][i] = t.get(i)[1]; }
        return r;
    }

    private static float[] areaAlpha(int ssize, int dsize, double scale) {
        List<Float> a = new ArrayList<>();
        areaWalk(ssize, dsize, scale, null, a);
        float[] r = new float[a.size()];
        for (int i = 0; i < r.length; i++) r[i] = a.get(i);
        return r;
    }

    private static void areaWalk(int ssize, int dsize, double scale, List<int[]> idx, List<Float> alpha) {
        for (int dx = 0; dx < dsize; dx++) {
            double f1 = dx * scale, f2 = f1 + scale;
            double cw = Math.min(scale, ssize - f1);
            int s1 = (int) Math.ceil(f1), s2 = (int) Math.floor(f2);
            s2 = Math.min(s2, ssize - 1);
            s1 = Math.min(s1, s2);
            if (s1 - f1 > 1e-3) {
                if (idx != null) idx.add(new int[] {dx, s1 - 1});
                if (alpha != null) alpha.add((float) ((s1 - f1) / cw));
            }
            for (int sx = s1; sx < s2; sx++) {
                if (idx != null) idx.add(new int[] {dx, sx});
                if (alpha != null) alpha.add((float) (1.0 / cw));
            }
            if (f2 - s2 > 1e-3) {
                if (idx != null) idx.add(new int[] {dx, s2});
                if (alpha != null) alpha.add((float) (Math.min(Math.min(f2 - s2, 1.), cw) / cw));
            }
        }
    }

    private static double cubicW(double x) {
        final double A = -0.75;
        x = Math.abs(x);
        if (x <= 1) return ((A + 2) * x - (A + 3)) * x * x + 1;
        if (x < 2) return ((A * x - 5 * A) * x + 8 * A) * x - 4 * A;
        return 0;
    }

    /** cv2.resize INTER_CUBIC (збільшення дрібного тексту). */
    static Gray resizeCubic(Gray g, int nw, int nh) {
        double sx = (double) g.w / nw, sy = (double) g.h / nh;
        double[] tmp = new double[nw * g.h];
        for (int x = 0; x < nw; x++) {
            double fx = (x + 0.5) * sx - 0.5;
            int ix = (int) Math.floor(fx);
            double t = fx - ix;
            double[] wv = {cubicW(1 + t), cubicW(t), cubicW(1 - t), cubicW(2 - t)};
            for (int y = 0; y < g.h; y++) {
                double s = 0;
                for (int k = 0; k < 4; k++) s += wv[k] * px(g, ix - 1 + k, y);
                tmp[y * nw + x] = s;
            }
        }
        byte[] o = new byte[nw * nh];
        for (int y = 0; y < nh; y++) {
            double fy = (y + 0.5) * sy - 0.5;
            int iy = (int) Math.floor(fy);
            double t = fy - iy;
            double[] wv = {cubicW(1 + t), cubicW(t), cubicW(1 - t), cubicW(2 - t)};
            for (int x = 0; x < nw; x++) {
                double s = 0;
                for (int k = 0; k < 4; k++) {
                    int yy = Math.min(Math.max(iy - 1 + k, 0), g.h - 1);
                    s += wv[k] * tmp[yy * nw + x];
                }
                o[y * nw + x] = sat(s);
            }
        }
        return new Gray(o, nw, nh);
    }

    static Gray rotate(Gray g, int deg) {
        switch (deg) {
            case 90: return new Gray(Img.rotate90cw(g.p, g.w, g.h), g.h, g.w);
            case 180: return new Gray(Img.rotate180(g.p, g.w, g.h), g.w, g.h);
            case 270: {
                byte[] r = Img.rotate180(Img.rotate90cw(g.p, g.w, g.h), g.h, g.w);
                return new Gray(r, g.h, g.w);
            }
            default: return g;
        }
    }

    static Gray rows(Gray g, int y0, int y1) {
        return new Gray(Arrays.copyOfRange(g.p, y0 * g.w, y1 * g.w), g.w, y1 - y0);
    }

    /** Вирізати чотирикутник у прямокутник cw x ch (cv2.getAffineTransform за 3 кутами + warpAffine, BORDER_REPLICATE). */
    /**
     * cv2.warpAffine(getAffineTransform(b[0,1,3] -> (0,0),(cw,0),(0,ch)), INTER_LINEAR, BORDER_REPLICATE) як в
     * OpenCV 5 (на ньому зроблено еталон курсової): обернена матриця у float, координата джерела
     * x·m0 + float(y·m1 + m2) з одним округленням, інтерполяція у float, округлення до парного.
     */
    static Gray warp(Gray g, Quad b, int cw, int ch) {
        double[] m = affine(new double[] {(float) b.x[0], (float) b.x[1], (float) b.x[3]},
                new double[] {(float) b.y[0], (float) b.y[1], (float) b.y[3]}, cw, ch);
        double d = m[0] * m[4] - m[1] * m[3];
        d = d != 0 ? 1. / d : 0.;
        double a11 = m[4] * d, a22 = m[0] * d, a12 = -m[1] * d, a21 = -m[3] * d;
        double b1 = -a11 * m[2] - a12 * m[5], b2 = -a21 * m[2] - a22 * m[5];
        float i0 = (float) a11, i1 = (float) a12, i2 = (float) b1, i3 = (float) a21, i4 = (float) a22, i5 = (float) b2;
        byte[] o = new byte[cw * ch];
        for (int y = 0; y < ch; y++) {
            float tx = i1 * y + i2, ty = i4 * y + i5;
            for (int x = 0; x < cw; x++) {
                float sx = (float) ((double) i0 * x + tx), sy = (float) ((double) i3 * x + ty);
                int ix = (int) Math.floor(sx), iy = (int) Math.floor(sy);
                float al = sx - ix, be = sy - iy;
                float p00 = px(g, ix, iy), p01 = px(g, ix + 1, iy), p10 = px(g, ix, iy + 1), p11 = px(g, ix + 1, iy + 1);
                float v0 = p00 + al * (p01 - p00), v1 = p10 + al * (p11 - p10);
                float v = v0 + be * (v1 - v0);
                o[y * cw + x] = (byte) Math.max(0, Math.min(255, (int) Math.rint(v)));
            }
        }
        return new Gray(o, cw, ch);
    }

    /** getAffineTransform: (x[i], y[i]) -> (0,0), (cw,0), (0,ch); результат [m00 m01 m02 m10 m11 m12]. */
    static double[] affine(double[] x, double[] y, int cw, int ch) {
        // розв'язок 6x6 як в OpenCV (LU з частковим вибором) для двох незалежних систем 3x3
        double[][] a = {{x[0], y[0], 1}, {x[1], y[1], 1}, {x[2], y[2], 1}};
        double[] u = solve3(a, new double[] {0, cw, 0}), v = solve3(a, new double[] {0, 0, ch});
        return new double[] {u[0], u[1], u[2], v[0], v[1], v[2]};
    }

    private static double[] solve3(double[][] a0, double[] b0) {
        double[][] a = {a0[0].clone(), a0[1].clone(), a0[2].clone()};
        double[] b = b0.clone();
        for (int i = 0; i < 3; i++) {
            int p = i;
            for (int k = i + 1; k < 3; k++) if (Math.abs(a[k][i]) > Math.abs(a[p][i])) p = k;
            double[] t = a[i]; a[i] = a[p]; a[p] = t;
            double tb = b[i]; b[i] = b[p]; b[p] = tb;
            for (int k = i + 1; k < 3; k++) {
                double f = a[k][i] / a[i][i];
                for (int j = i; j < 3; j++) a[k][j] -= f * a[i][j];
                b[k] -= f * b[i];
            }
        }
        double[] r = new double[3];
        for (int i = 2; i >= 0; i--) {
            double s = b[i];
            for (int j = i + 1; j < 3; j++) s -= a[i][j] * r[j];
            r[i] = s / a[i][i];
        }
        return r;
    }

    // ------------------------------------------------------------------ детектор

    static int r32(double v) { return Math.max(32, (int) (Math.rint(v / 32) * 32)); }

    static Quad order(double[] x, double[] y) {
        DbPost.Box b = DbPost.orderClockwise(x, y);
        Quad q = new Quad();
        for (int i = 0; i < 4; i++) { q.x[i] = b.x[i]; q.y[i] = b.y[i]; }
        return q;
    }

    static Quad rectQuad(Geom.Rect r) {
        double[][] c = r.corners();
        double[] x = new double[4], y = new double[4];
        for (int i = 0; i < 4; i++) { x[i] = c[i][0]; y[i] = c[i][1]; }
        return order(x, y);
    }

    /** Рамки рядків на [g] у його координатах. */
    static List<Quad> detect(Gray g, Reader rd) throws Exception {
        int H = g.h, W = g.w;
        double r = 1.0;
        if (Math.min(W, H) < 736) r = 736.0 / Math.min(W, H);
        if (Math.max(W, H) * r > 2400) r = 2400.0 / Math.max(W, H);
        int rw = r32(W * r), rh = r32(H * r);
        Gray x = resizeLinear(g, rw, rh);
        float[] t = new float[3 * rw * rh];
        int plane = rw * rh;
        for (int i = 0; i < plane; i++) {
            float v = (x.p[i] & 255) / 127.5f - 1f;
            t[i] = v; t[plane + i] = v; t[2 * plane + i] = v;
        }
        rd.detCalls.incrementAndGet();
        float[] prob = rd.run.det(t, rh, rw);
        byte[] mask = new byte[plane];
        for (int i = 0; i < plane; i++) mask[i] = (byte) (prob[i] > 0.3f ? 1 : 0);
        byte[] d = new byte[plane]; // cv2.dilate 2x2
        for (int yy = 0; yy < rh; yy++)
            for (int xx = 0; xx < rw; xx++) {
                int v = mask[yy * rw + xx];
                if (xx > 0) v |= mask[yy * rw + xx - 1];
                if (yy > 0) v |= mask[(yy - 1) * rw + xx];
                if (xx > 0 && yy > 0) v |= mask[(yy - 1) * rw + xx - 1];
                d[yy * rw + xx] = (byte) v;
            }
        mask = d;
        List<Quad> boxes = new ArrayList<>();
        boolean[] seen = new boolean[plane];
        int[] stack = new int[plane];
        double[] px = new double[1024], py = new double[1024];
        int cand = 0;
        for (int start = 0; start < plane && cand < 1000; start++) {
            if (mask[start] == 0 || seen[start]) continue;
            cand++;
            int sp = 0, n = 0;
            stack[sp++] = start;
            seen[start] = true;
            while (sp > 0) {
                int p = stack[--sp];
                int cx = p % rw, cy = p / rw;
                if (n == px.length) { px = Arrays.copyOf(px, n * 2); py = Arrays.copyOf(py, n * 2); }
                px[n] = cx; py[n] = cy; n++;
                for (int dy = -1; dy <= 1; dy++)
                    for (int dx = -1; dx <= 1; dx++) {
                        int nx = cx + dx, ny = cy + dy;
                        if (nx < 0 || ny < 0 || nx >= rw || ny >= rh) continue;
                        int q = ny * rw + nx;
                        if (mask[q] != 0 && !seen[q]) { seen[q] = true; stack[sp++] = q; }
                    }
            }
            Geom.Rect rect = Geom.minAreaRect(px, py, n);
            if (Math.min(rect.w, rect.h) < 3) continue;
            if (polyMean(prob, rw, rh, rect.corners()) < 0.5) continue;
            double dd = rect.w * rect.h * UNCLIP / (2 * (rect.w + rect.h));
            rect.w += 2 * dd;
            rect.h += 2 * dd;
            if (Math.min(rect.w, rect.h) < 5) continue;
            // поздовжній запас: довша сторона подовжується на PAD висоти рядка з кожного боку
            if (rect.w >= rect.h) rect.w += 2 * PAD * rect.h;
            else rect.h += 2 * PAD * rect.w;
            double[][] c = rect.corners();
            double[] qx = new double[4], qy = new double[4];
            for (int i = 0; i < 4; i++) { qx[i] = c[i][0] * W / rw; qy[i] = c[i][1] * H / rh; }
            boxes.add(order(qx, qy));
        }
        return boxes;
    }

    /** Середня ймовірність у многокутнику з цілими (відкинута дробова частина) вершинами, як cv2.fillPoly + mean. */
    static double polyMean(float[] prob, int w, int h, double[][] c) {
        int[] qx = new int[4], qy = new int[4];
        int ymin = Integer.MAX_VALUE, ymax = Integer.MIN_VALUE;
        for (int i = 0; i < 4; i++) {
            qx[i] = (int) c[i][0];
            qy[i] = (int) c[i][1];
            ymin = Math.min(ymin, qy[i]);
            ymax = Math.max(ymax, qy[i]);
        }
        ymin = Math.max(ymin, 0);
        ymax = Math.min(ymax, h - 1);
        double sum = 0;
        long cnt = 0;
        int xmin = Integer.MAX_VALUE, xmax = Integer.MIN_VALUE;
        for (int i = 0; i < 4; i++) { xmin = Math.min(xmin, qx[i]); xmax = Math.max(xmax, qx[i]); }
        xmin = Math.max(xmin, 0);
        xmax = Math.min(xmax, w - 1);
        for (int y = ymin; y <= ymax; y++)
            for (int x = xmin; x <= xmax; x++)
                if (inside(qx, qy, x, y)) { sum += prob[y * w + x]; cnt++; }
        return cnt == 0 ? 0 : sum / cnt;
    }

    private static boolean inside(int[] qx, int[] qy, int x, int y) {
        boolean pos = false, neg = false;
        for (int i = 0; i < 4; i++) {
            int j = (i + 1) & 3;
            long cr = (long) (qx[j] - qx[i]) * (y - qy[i]) - (long) (qy[j] - qy[i]) * (x - qx[i]);
            if (cr > 0) pos = true;
            else if (cr < 0) neg = true;
        }
        return !(pos && neg);
    }

    // ------------------------------------------------------------------ читач

    /** Прочитати рамку [b] з розтягненнями [stretch] (CTC не зливає подвоєні цифри у розтягненому рядку). */
    static Read read(Gray g, Quad b, Reader rd, double[] stretch) throws Exception {
        int cw = (int) Math.max(b.len(0, 1), b.len(3, 2));
        int ch = (int) Math.max(b.len(0, 3), b.len(1, 2));
        if (cw < 4 || ch < 4) return new Read("", 0.0);
        Gray c = warp(g, b, cw, ch);
        if (ch > 1.5 * cw) { // cv2.ROTATE_90_COUNTERCLOCKWISE
            c = rotate(c, 270);
            int t = cw; cw = ch; ch = t;
        }
        Read best = null;
        for (double st : stretch) {
            // невпевнений рядок, розтягнутий, читається впевненіше без втрати цифр і розділювачів;
            // упевнений (>= 0,9) не замінюється, тож і розтягувати його марно
            if (best != null && best.conf >= 0.9) break;
            int nw = (int) Math.min(Math.max(Math.rint(48.0 * cw / ch * st), 48), 3200);
            Gray x = resizeLinear(c, nw, 48);
            float[] t = new float[3 * 48 * nw];
            int plane = 48 * nw;
            for (int i = 0; i < plane; i++) {
                float v = (x.p[i] & 255) / 127.5f - 1f;
                t[i] = v; t[plane + i] = v; t[2 * plane + i] = v;
            }
            int[] tc = new int[2];
            rd.recCalls.incrementAndGet();
            float[] out = rd.run.rec(t, 1, nw, tc);
            float[] cf = new float[1];
            String s = Ctc.decode(out, 0, tc[0], tc[1], rd.chars, cf).trim();
            Read r = new Read(s, cf[0]);
            if (best == null) best = r;
            else if (r.conf > best.conf + 0.1 && digits(r.text) >= digits(best.text) && seps(r.text) >= seps(best.text)) best = r;
        }
        return best;
    }

    static int digits(String s) {
        int n = 0;
        for (int i = 0; i < s.length(); i++) if (Character.isDigit(s.charAt(i))) n++;
        return n;
    }

    static int seps(String s) {
        int n = 0;
        for (int i = 0; i < s.length(); i++) if (s.charAt(i) == '.' || s.charAt(i) == ',') n++;
        return n;
    }

    static final double[] STRETCH = {1.0, 2.0};

    // ------------------------------------------------------------------ прохід

    private static double[] geo(Quad b) { // min x, max x, mean y, h, w
        return new double[] {b.minX(), b.maxX(), b.meanY(), b.len(3, 0), b.len(1, 0)};
    }

    /** Злиття сусідніх рамок одного рядка з малим проміжком (детектор розриває розріджений шрифт). */
    static List<Quad> mergeAdjacent(List<Quad> boxes) {
        List<Quad> bs = new ArrayList<>(boxes);
        boolean changed = true;
        while (changed) {
            changed = false;
            bs.sort(Comparator.comparingDouble(Quad::minX));
            outer:
            for (int i = 0; i < bs.size(); i++) {
                double[] gi = geo(bs.get(i));
                if (gi[4] < gi[3]) continue;
                for (int j = i + 1; j < bs.size(); j++) {
                    double[] gj = geo(bs.get(j));
                    if (gj[4] < gj[3]) continue;
                    double hi = gi[3], hj = gj[3], gap = gj[0] - gi[1];
                    if (Math.abs(gi[2] - gj[2]) < 0.35 * Math.min(hi, hj) && 0.7 < hi / hj && hi / hj < 1.4
                            && -0.3 * hi < gap && gap < 0.8 * Math.min(hi, hj)) {
                        double[] xs = new double[8], ys = new double[8];
                        for (int k = 0; k < 4; k++) {
                            xs[k] = bs.get(i).x[k]; ys[k] = bs.get(i).y[k];
                            xs[4 + k] = bs.get(j).x[k]; ys[4 + k] = bs.get(j).y[k];
                        }
                        Quad m = rectQuad(Geom.minAreaRect(xs, ys, 8));
                        List<Quad> nb = new ArrayList<>();
                        for (int k = 0; k < bs.size(); k++) if (k != i && k != j) nb.add(bs.get(k));
                        nb.add(m);
                        bs = nb;
                        changed = true;
                        break outer;
                    }
                }
            }
        }
        return bs;
    }

    /** Дрібний текст: збільшене зображення ділиться на смуги з перекриттям, кожна детектується окремо. */
    static List<Quad> detectTiled(Gray g, Reader rd) throws Exception {
        int H = g.h, T = 2000, O = 300;
        List<Quad> boxes = new ArrayList<>();
        for (int y0 = 0; y0 < Math.max(1, H - O); y0 += T - O) {
            int y1 = Math.min(H, y0 + T);
            for (Quad b : detect(rows(g, y0, y1), rd)) {
                Quad s = b.shiftedY(y0);
                double cy = s.meanY();
                if (y0 > 0 && cy < y0 + O / 2.0) continue;
                if (y1 < H && cy > y1 - O / 2.0) continue;
                boxes.add(s);
            }
            if (y1 == H) break;
        }
        return boxes;
    }

    static List<Row> pass(Gray g, Reader rd) throws Exception {
        List<Quad> boxes = detect(g, rd);
        double[] hs = new double[boxes.size()];
        for (int i = 0; i < hs.length; i++) hs[i] = Math.min(boxes.get(i).len(0, 3), boxes.get(i).len(0, 1));
        Arrays.sort(hs);
        double hmed = hs.length > 0 ? hs[hs.length / 2] : 99;
        double scale = 1.0;
        Gray gg = g;
        if (0 < hmed && hmed < 26) { // рядки нижчі за ~26 пікселів: збільшити й детектувати смугами
            scale = Math.min(2.5, 34 / hmed);
            gg = resizeCubic(g, (int) (g.w * scale), (int) (g.h * scale));
            boxes = detectTiled(gg, rd);
        }
        boxes = mergeAdjacent(boxes);
        List<Row> rows = new ArrayList<>();
        final Gray gf = gg;
        List<java.util.concurrent.Callable<Read>> jobs = new ArrayList<>();
        for (Quad b : boxes) jobs.add(() -> read(gf, b, rd, STRETCH));
        List<Read> reads = rd.parallel(jobs);
        for (int i = 0; i < boxes.size(); i++) {
            Read r = reads.get(i);
            Quad b = boxes.get(i);
            if (!r.text.isEmpty()) rows.add(new Row(scale == 1.0 ? b : b.scaled(scale), r.text, r.conf));
        }
        return rows;
    }

    static double mconf(List<Row> rows) {
        double s = 0;
        int n = 0;
        for (Row r : rows) { s += r.conf * r.text.length(); n += r.text.length(); }
        return n > 0 ? s / n : 0.0;
    }

    private static int tall(List<Row> rows) {
        int n = 0;
        for (Row r : rows) if (r.b.len(0, 3) > r.b.len(0, 1)) n++;
        return n;
    }

    private static final class Cand {
        final int rot;
        final Gray g;
        final List<Row> rows;

        Cand(int rot, Gray g, List<Row> rows) { this.rot = rot; this.g = g; this.rows = rows; }

        double score() {
            int tl = tall(rows);
            return mconf(rows) - (!rows.isEmpty() && tl * 2 > rows.size() ? 0.3 : 0);
        }
    }

    /**
     * Пропуск перевірки поворотів: на 130 чеках правильним був поворот 0, коли оцінка першого проходу >= 0,83,
     * а інші повороти перемагали, коли вона <= 0,69. Поріг посередині, з запасом.
     */
    static boolean FAST_ROT = System.getenv("NO_FASTROT") == null;
    static final double ROT_SKIP = 0.78;

    /** Повне розпізнавання сірого фото [g0]: поворот, рамки, текст, фрагменти. */
    static Result run(Gray g0, Reader rd) throws Exception {
        Gray g = g0;
        double s = 2400.0 / Math.max(g.w, g.h);
        if (s < 1) g = resizeArea(g, (int) (g.w * s), (int) (g.h * s));
        List<Row> rows = pass(g, rd);
        int tl = tall(rows);
        List<Cand> cands = new ArrayList<>();
        cands.add(new Cand(0, g, rows));
        List<Integer> rots = new ArrayList<>();
        if (FAST_ROT && cands.get(0).score() >= ROT_SKIP) { // прямий чек читається впевнено: інші повороти не потрібні
            Result res = new Result();
            res.rotation = 0;
            res.g = g;
            res.conf = mconf(rows);
            res.frags.addAll(toFrags(g, rows, 0, res.conf));
            return res;
        }
        if (!rows.isEmpty() && tl * 2 > rows.size()) { rots.add(90); rots.add(270); }
        rots.add(180);
        for (int r : rots) {
            Gray gr = rotate(g, r);
            cands.add(new Cand(r, gr, pass(gr, rd)));
        }
        if (tl * 2 > rows.size()) {
            Cand best90 = null;
            for (Cand c : cands)
                if ((c.rot == 90 || c.rot == 270) && (best90 == null || mconf(c.rows) > mconf(best90.rows))) best90 = c;
            Gray gr = rotate(best90.g, 180);
            cands.add(new Cand((best90.rot + 180) % 360, gr, pass(gr, rd)));
        }
        Cand best = cands.get(0);
        for (Cand c : cands) if (c.score() > best.score()) best = c;
        Result res = new Result();
        res.rotation = best.rot;
        res.g = best.g;
        res.conf = mconf(best.rows);
        res.frags.addAll(toFrags(best.g, best.rows, best.rot, res.conf));
        return res;
    }

    /** Рамки -> фрагменти: загальний нахил знімається, ширина - без поздовжнього запасу. */
    static List<Frag> toFrags(Gray g, List<Row> rows, int rot, double conf) {
        int n = rows.size();
        double[] cx = new double[n], cy = new double[n], bw = new double[n], bh = new double[n], ang = new double[n];
        List<Double> angs = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            Quad b = rows.get(i).b;
            cx[i] = (b.x[0] + b.x[1] + b.x[2] + b.x[3]) / 4;
            cy[i] = (b.y[0] + b.y[1] + b.y[2] + b.y[3]) / 4;
            bw[i] = Math.max(b.len(1, 0), b.len(2, 3));
            bh[i] = Math.max(b.len(3, 0), b.len(2, 1));
            ang[i] = Math.atan2(b.y[1] - b.y[0], b.x[1] - b.x[0]);
            if (bw[i] > 3 * bh[i]) angs.add(ang[i]);
        }
        angs.sort(null);
        double a = angs.isEmpty() ? 0.0 : angs.get(angs.size() / 2);
        double cs = Math.cos(-a), sn = Math.sin(-a);
        List<Frag> out = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            Row r = rows.get(i);
            double bw0 = Math.max(1.0, bw[i] - 2 * PAD * bh[i]);
            double rx = cx[i] * cs - cy[i] * sn, ry = cx[i] * sn + cy[i] * cs;
            Frag f = new Frag();
            f.boxId = i;
            f.text = r.text;
            f.conf = r.conf;
            f.x = rx;
            f.y = ry;
            f.w = bw0;
            f.h = bh[i];
            f.xLeft = rx - bw0 / 2;
            f.xRight = rx + bw0 / 2;
            f.imgW = g.w;
            f.imgH = g.h;
            f.rotation = rot;
            f.receiptConf = conf;
            f.angle = a;
            out.add(f);
        }
        return out;
    }
}
