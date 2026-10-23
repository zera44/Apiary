package org.apiary.paddle_ocr;

import java.util.Arrays;

/** Геометрія без Android: опукла оболонка й найменший обертовий прямокутник (як cv2.minAreaRect). */
final class Geom {
    private Geom() {}

    /** Прямокутник: центр, довжини сторін [w] вздовж одиничного вектора u, [h] вздовж v = (-uy, ux). */
    static final class Rect {
        double cx, cy, w, h, ux, uy;

        /** Кути: лівий-верхній, правий-верхній, правий-нижній, лівий-нижній у системі (u, v). */
        double[][] corners() {
            double vx = -uy, vy = ux, hw = w / 2, hh = h / 2;
            return new double[][] {
                {cx - ux * hw - vx * hh, cy - uy * hw - vy * hh},
                {cx + ux * hw - vx * hh, cy + uy * hw - vy * hh},
                {cx + ux * hw + vx * hh, cy + uy * hw + vy * hh},
                {cx - ux * hw + vx * hh, cy - uy * hw + vy * hh},
            };
        }
    }

    private static double cross(double ox, double oy, double ax, double ay, double bx, double by) {
        return (ax - ox) * (by - oy) - (ay - oy) * (bx - ox);
    }

    /** Опукла оболонка (Ендрю). Повертає пари {x, y} проти годинникової. */
    static double[][] hull(double[] xs, double[] ys, int n) {
        Integer[] idx = new Integer[n];
        for (int i = 0; i < n; i++) idx[i] = i;
        Arrays.sort(idx, (a, b) -> xs[a] != xs[b] ? Double.compare(xs[a], xs[b]) : Double.compare(ys[a], ys[b]));
        if (n <= 2) {
            double[][] r = new double[n][];
            for (int i = 0; i < n; i++) r[i] = new double[] {xs[idx[i]], ys[idx[i]]};
            return r;
        }
        double[][] h = new double[2 * n][];
        int k = 0;
        for (int i = 0; i < n; i++) {
            double px = xs[idx[i]], py = ys[idx[i]];
            while (k >= 2 && cross(h[k - 2][0], h[k - 2][1], h[k - 1][0], h[k - 1][1], px, py) <= 0) k--;
            h[k++] = new double[] {px, py};
        }
        for (int i = n - 2, t = k + 1; i >= 0; i--) {
            double px = xs[idx[i]], py = ys[idx[i]];
            while (k >= t && cross(h[k - 2][0], h[k - 2][1], h[k - 1][0], h[k - 1][1], px, py) <= 0) k--;
            h[k++] = new double[] {px, py};
        }
        return Arrays.copyOf(h, Math.max(1, k - 1));
    }

    /** Найменший за площею обертовий прямокутник навколо точок. */
    static Rect minAreaRect(double[] xs, double[] ys, int n) {
        double[][] h = hull(xs, ys, n);
        Rect best = new Rect();
        best.ux = 1;
        best.uy = 0;
        if (h.length == 0) return best;
        if (h.length == 1) {
            best.cx = h[0][0];
            best.cy = h[0][1];
            return best;
        }
        double bestArea = Double.MAX_VALUE;
        int m = h.length;
        for (int i = 0; i < m; i++) {
            double ex = h[(i + 1) % m][0] - h[i][0], ey = h[(i + 1) % m][1] - h[i][1];
            double len = Math.hypot(ex, ey);
            if (len == 0) continue;
            double ux = ex / len, uy = ey / len, vx = -uy, vy = ux;
            double minU = Double.MAX_VALUE, maxU = -Double.MAX_VALUE, minV = Double.MAX_VALUE, maxV = -Double.MAX_VALUE;
            for (double[] p : h) {
                double pu = p[0] * ux + p[1] * uy, pv = p[0] * vx + p[1] * vy;
                if (pu < minU) minU = pu;
                if (pu > maxU) maxU = pu;
                if (pv < minV) minV = pv;
                if (pv > maxV) maxV = pv;
            }
            double area = (maxU - minU) * (maxV - minV);
            if (area < bestArea) {
                bestArea = area;
                best.w = maxU - minU;
                best.h = maxV - minV;
                best.ux = ux;
                best.uy = uy;
                double cu = (minU + maxU) / 2, cv = (minV + maxV) / 2;
                best.cx = ux * cu + vx * cv;
                best.cy = uy * cu + vy * cv;
            }
        }
        if (bestArea == Double.MAX_VALUE) { // усі точки на одній прямій
            double[] a = h[0], b = h[m - 1];
            double len = Math.hypot(b[0] - a[0], b[1] - a[1]);
            best.cx = (a[0] + b[0]) / 2;
            best.cy = (a[1] + b[1]) / 2;
            best.w = len;
            best.h = 0;
            if (len > 0) {
                best.ux = (b[0] - a[0]) / len;
                best.uy = (b[1] - a[1]) / len;
            }
        }
        return best;
    }
}
