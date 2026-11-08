package org.apiary.paddle_ocr;

import java.util.HashMap;
import java.util.Map;
import java.util.regex.Pattern;

import org.apiary.paddle_ocr.OcrV2.Frag;
import org.apiary.paddle_ocr.OcrV2.Gray;
import org.apiary.paddle_ocr.OcrV2.Quad;

/**
 * Примітиви, які дочитування (lib/logic/fz2/recover.dart) бере в плагіна: рамка у повернутій системі фрагментів,
 * поріг Оцу й тісна рамка за чорнилом для виродженого фрагмента, регулярні вирази з юнікодними \d, \w, \b як у Python.
 */
final class OcrPrim {
    private OcrPrim() {}

    private static final Map<String, Pattern> CACHE = new HashMap<>();

    static Pattern re(String p) {
        synchronized (CACHE) {
            Pattern r = CACHE.get(p);
            if (r == null) { r = Pattern.compile(p, Pattern.UNICODE_CHARACTER_CLASS); CACHE.put(p, r); }
            return r;
        }
    }

    static boolean search(String p, String s) { return re(p).matcher(s).find(); }

    /** Рамка (x1..x2, y1..y2) у системі фрагментів, повернута на нахил фото. */
    static Quad quad(double a, double x1, double x2, double y1, double y2) {
        double c = Math.cos(a), s = Math.sin(a);
        double[][] p = {{x1, y1}, {x2, y1}, {x2, y2}, {x1, y2}};
        Quad q = new Quad();
        for (int i = 0; i < 4; i++) {
            float px = (float) p[i][0], py = (float) p[i][1];
            q.x[i] = (float) (px * c - py * s);
            q.y[i] = (float) (px * s + py * c);
        }
        return q;
    }

    /** Поріг Оцу (cv2.THRESH_OTSU). */
    static int otsu(Gray g) {
        int[] hist = new int[256];
        for (byte b : g.p) hist[b & 255]++;
        int n = g.p.length;
        double mu = 0;
        for (int i = 0; i < 256; i++) mu += i * (double) hist[i];
        mu /= n;
        double q1 = 0, mu1 = 0, maxVal = 0;
        int best = 0;
        for (int i = 0; i < 256; i++) {
            double p_i = hist[i] / (double) n;
            double q2;
            mu1 *= q1;
            q1 += p_i;
            q2 = 1. - q1;
            if (Math.min(q1, q2) < 1e-7 || Math.max(q1, q2) > 1. - 1e-7) continue;
            mu1 = (mu1 + i * p_i) / q1;
            double mu2 = (mu - q1 * mu1) / q2;
            double sigma = q1 * q2 * (mu1 - mu2) * (mu1 - mu2);
            if (sigma > maxVal) { maxVal = sigma; best = i; }
        }
        return best;
    }

    /** Тісна рамка за чорнилом навколо центру (великий шрифт із виродженою рамкою). */
    static void degenBox(Frag f, Gray g, double a) {
        double h = f.h;
        double x1 = f.x - 3 * h, x2 = f.x + 3 * h, y1 = f.y - 0.3 * h, y2 = f.y + 0.3 * h;
        int cw = (int) (x2 - x1), ch = (int) (y2 - y1);
        if (cw < 1 || ch < 1) return;
        Gray cr = OcrV2.warp(g, quad(a, x1, x2, y1, y2), cw, ch);
        int t = otsu(cr);
        boolean[] ink = new boolean[cw];
        for (int x = 0; x < cw; x++) {
            double s = 0;
            for (int y = 0; y < ch; y++) s += (cr.p[y * cw + x] & 255) <= t ? 255 : 0;
            ink[x] = s / ch > 0.06 * 255;
        }
        int cx = cw / 2, gap = (int) Math.max(8, 0.22 * h);
        int L = cx, R = cx;
        while (L > 0 && any(ink, Math.max(0, L - gap), L)) L--;
        while (R < cw - 1 && any(ink, R, Math.min(cw, R + gap))) R++;
        if (R - L > 0.3 * h) {
            f.xLeft = x1 + L;
            f.xRight = x1 + R;
            f.x = (f.xLeft + f.xRight) / 2;
            f.w = R - L;
            double y1b = f.y - 0.7 * h, y2b = f.y + 0.7 * h;
            int ww = R - L, hh = (int) (y2b - y1b);
            if (ww < 1 || hh < 1) return;
            Gray c2 = OcrV2.warp(g, quad(a, x1 + L, x1 + R, y1b, y2b), ww, hh);
            int t2 = otsu(c2);
            boolean[] rink = new boolean[hh];
            for (int y = 0; y < hh; y++) {
                double s = 0;
                for (int x = 0; x < ww; x++) s += (c2.p[y * ww + x] & 255) <= t2 ? 255 : 0;
                rink[y] = s / ww > 0.06 * 255;
            }
            int cy = hh / 2, gp = (int) Math.max(3, 0.05 * h);
            int T = cy, B = cy;
            while (T > 0 && any(rink, Math.max(0, T - gp), T)) T--;
            while (B < hh - 1 && any(rink, B, Math.min(hh, B + gp))) B++;
            if (B - T > 0.2 * h) { f.y = y1b + (T + B) / 2.0; f.h = (B - T) * 1.2; }
        }
    }

    private static boolean any(boolean[] v, int a, int b) {
        for (int i = a; i < b; i++) if (v[i]) return true;
        return false;
    }
}
