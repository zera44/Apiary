package org.apiary.paddle_ocr;

/** Операції над сірим зображенням без Android (піксель = байт 0..255). */
final class Img {
    private Img() {}

    /** ARGB -> сіре. Береться канал з найбільшим контрастом (R, G, B або яскравість): чек при кольоровому світлі чіткіший в одному каналі. */
    static byte[] bestGray(int[] argb, int n) {
        double[] sum = new double[4], sq = new double[4];
        for (int i = 0; i < n; i++) {
            int p = argb[i];
            int r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
            double l = 0.299 * r + 0.587 * g + 0.114 * b;
            sum[0] += r; sq[0] += (double) r * r;
            sum[1] += g; sq[1] += (double) g * g;
            sum[2] += b; sq[2] += (double) b * b;
            sum[3] += l; sq[3] += l * l;
        }
        int best = 3;
        double bs = -1;
        for (int k = 0; k < 4; k++) {
            double m = sum[k] / n, sd = Math.sqrt(Math.max(0, sq[k] / n - m * m));
            if (sd > bs) { bs = sd; best = k; }
        }
        byte[] out = new byte[n];
        for (int i = 0; i < n; i++) {
            int p = argb[i];
            int r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
            int v = best == 0 ? r : best == 1 ? g : best == 2 ? b : (int) Math.round(0.299 * r + 0.587 * g + 0.114 * b);
            out[i] = (byte) v;
        }
        return out;
    }

    static int px(byte[] g, int w, int h, int x, int y) {
        if (x < 0) x = 0; else if (x >= w) x = w - 1;
        if (y < 0) y = 0; else if (y >= h) y = h - 1;
        return g[y * w + x] & 255;
    }

    /** Білінійне значення в дробовій точці (центр пікселя - ціла координата). */
    static float sample(byte[] g, int w, int h, double x, double y) {
        int x0 = (int) Math.floor(x), y0 = (int) Math.floor(y);
        double fx = x - x0, fy = y - y0;
        double a = px(g, w, h, x0, y0), b = px(g, w, h, x0 + 1, y0), c = px(g, w, h, x0, y0 + 1), d = px(g, w, h, x0 + 1, y0 + 1);
        return (float) ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy);
    }

    /** Вхід детектора: сіре, змінене до rw x rh (як cv2.resize INTER_LINEAR), у [-1, 1], 3 однакові канали (CHW). */
    static float[] detTensor(byte[] g, int w, int h, int rw, int rh) {
        float[] t = new float[3 * rw * rh];
        double sx = (double) w / rw, sy = (double) h / rh;
        int plane = rw * rh;
        for (int y = 0; y < rh; y++) {
            double fy = (y + 0.5) * sy - 0.5;
            for (int x = 0; x < rw; x++) {
                double fx = (x + 0.5) * sx - 0.5;
                float v = sample(g, w, h, fx, fy) / 127.5f - 1f;
                int o = y * rw + x;
                t[o] = v;
                t[plane + o] = v;
                t[2 * plane + o] = v;
            }
        }
        return t;
    }

    /** Вирізати чотирикутник [b] у рівний прямокутник (афінно, білінійно). outWH = {ширина, висота}. */
    static byte[] warp(byte[] g, int w, int h, DbPost.Box b, int[] outWH) {
        int cw = Math.max(1, (int) Math.max(Math.hypot(b.x[0] - b.x[1], b.y[0] - b.y[1]), Math.hypot(b.x[3] - b.x[2], b.y[3] - b.y[2])));
        int ch = Math.max(1, (int) Math.max(Math.hypot(b.x[0] - b.x[3], b.y[0] - b.y[3]), Math.hypot(b.x[1] - b.x[2], b.y[1] - b.y[2])));
        byte[] o = new byte[cw * ch];
        double ax = (b.x[1] - b.x[0]) / cw, ay = (b.y[1] - b.y[0]) / cw;
        double bx = (b.x[3] - b.x[0]) / ch, by = (b.y[3] - b.y[0]) / ch;
        for (int y = 0; y < ch; y++)
            for (int x = 0; x < cw; x++)
                o[y * cw + x] = (byte) Math.round(Math.min(255f, Math.max(0f, sample(g, w, h, b.x[0] + ax * x + bx * y, b.y[0] + ay * x + by * y))));
        outWH[0] = cw;
        outWH[1] = ch;
        return o;
    }

    static final int REC_H = 48;

    /** Ширина тензора читача для кропа cw x ch: висота 48, довжина зберігає пропорцію. */
    static int recWidth(int cw, int ch) {
        long w = Math.round((double) REC_H * cw / Math.max(1, ch));
        return (int) Math.min(Math.max(w, 48), 3200);
    }

    /** Кроп -> CHW у [-1, 1] шириною [nw] у [dst] (сторінка [n] з [maxW] колонок, решта - білий). */
    static void recTensor(byte[] crop, int cw, int ch, int nw, float[] dst, int n, int count, int maxW) {
        double sx = (double) cw / nw, sy = (double) ch / REC_H;
        int plane = REC_H * maxW, base = n * 3 * plane;
        for (int y = 0; y < REC_H; y++) {
            double fy = (y + 0.5) * sy - 0.5;
            for (int x = 0; x < nw; x++) {
                float v = sample(crop, cw, ch, (x + 0.5) * sx - 0.5, fy) / 127.5f - 1f;
                int o = base + y * maxW + x;
                dst[o] = v;
                dst[o + plane] = v;
                dst[o + 2 * plane] = v;
            }
        }
    }

    static byte[] rotate90cw(byte[] g, int w, int h) {
        byte[] o = new byte[g.length];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) o[x * h + (h - 1 - y)] = g[y * w + x];
        return o;
    }

    static byte[] rotate180(byte[] g, int w, int h) {
        byte[] o = new byte[g.length];
        for (int i = 0; i < g.length; i++) o[g.length - 1 - i] = g[i];
        return o;
    }
}
