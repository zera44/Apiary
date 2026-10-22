package org.apiary.paddle_ocr;

import java.util.ArrayList;
import java.util.List;

/**
 * Постобробка детектора DB (як у PaddleOCR / RapidOCR): карта ймовірностей -> маска -> зв'язні області ->
 * обертові прямокутники -> розширення (unclip) -> координати на вихідному зображенні.
 */
final class DbPost {
    private DbPost() {}

    /** Чотирикутник: лівий-верхній, правий-верхній, правий-нижній, лівий-нижній (координати оригіналу). */
    static final class Box {
        final double[] x = new double[4], y = new double[4];
        double score;

        double width() { return Math.max(Math.hypot(x[0] - x[1], y[0] - y[1]), Math.hypot(x[3] - x[2], y[3] - y[2])); }
        double height() { return Math.max(Math.hypot(x[0] - x[3], y[0] - y[3]), Math.hypot(x[1] - x[2], y[1] - y[2])); }
        double angle() { return Math.atan2(y[1] - y[0], x[1] - x[0]); }
        double centerX() { return (x[0] + x[1] + x[2] + x[3]) / 4; }
        double centerY() { return (y[0] + y[1] + y[2] + y[3]) / 4; }
    }

    static List<Box> boxes(float[] prob, int mw, int mh, int srcW, int srcH,
                           float thresh, float boxThresh, double unclipRatio, boolean dilate, int maxCandidates) {
        byte[] mask = new byte[mw * mh];
        for (int i = 0; i < mask.length; i++) mask[i] = (byte) (prob[i] > thresh ? 1 : 0);
        if (dilate) { // cv2.dilate з ядром 2x2 (якір у (1,1)): піксель + сусіди зліва/зверху
            byte[] d = new byte[mask.length];
            for (int y = 0; y < mh; y++)
                for (int x = 0; x < mw; x++) {
                    int v = mask[y * mw + x];
                    if (x > 0) v |= mask[y * mw + x - 1];
                    if (y > 0) v |= mask[(y - 1) * mw + x];
                    if (x > 0 && y > 0) v |= mask[(y - 1) * mw + x - 1];
                    d[y * mw + x] = (byte) v;
                }
            mask = d;
        }
        List<Box> out = new ArrayList<>();
        boolean[] seen = new boolean[mask.length];
        int[] stack = new int[mask.length];
        double[] px = new double[1024], py = new double[1024];
        int candidates = 0;
        for (int start = 0; start < mask.length && candidates < maxCandidates; start++) {
            if (mask[start] == 0 || seen[start]) continue;
            candidates++;
            int sp = 0, n = 0;
            stack[sp++] = start;
            seen[start] = true;
            while (sp > 0) {
                int p = stack[--sp];
                int x = p % mw, y = p / mw;
                if (n == px.length) { px = java.util.Arrays.copyOf(px, n * 2); py = java.util.Arrays.copyOf(py, n * 2); }
                px[n] = x; py[n] = y; n++;
                for (int dy = -1; dy <= 1; dy++)
                    for (int dx = -1; dx <= 1; dx++) {
                        int nx = x + dx, ny = y + dy;
                        if (nx < 0 || ny < 0 || nx >= mw || ny >= mh) continue;
                        int q = ny * mw + nx;
                        if (mask[q] != 0 && !seen[q]) { seen[q] = true; stack[sp++] = q; }
                    }
            }
            Geom.Rect r = Geom.minAreaRect(px, py, n);
            if (Math.min(r.w, r.h) < 3) continue;
            double score = fastScore(prob, mw, mh, r.corners());
            if (score < boxThresh) continue;
            double dist = r.w * r.h * unclipRatio / (2 * (r.w + r.h));
            r.w += 2 * dist;
            r.h += 2 * dist;
            if (Math.min(r.w, r.h) < 5) continue;
            double[][] c = r.corners();
            // у координати оригіналу, округлення й обрізання як у RapidOCR
            double[] cx = new double[4], cy = new double[4];
            for (int i = 0; i < 4; i++) {
                cx[i] = Math.min(Math.max(Math.rint(c[i][0] / mw * srcW), 0), srcW);
                cy[i] = Math.min(Math.max(Math.rint(c[i][1] / mh * srcH), 0), srcH);
            }
            Box b = orderClockwise(cx, cy);
            for (int i = 0; i < 4; i++) { // clip_det_res
                b.x[i] = (int) Math.min(Math.max(b.x[i], 0), srcW - 1);
                b.y[i] = (int) Math.min(Math.max(b.y[i], 0), srcH - 1);
            }
            if ((int) b.width() <= 3 || (int) b.height() <= 3) continue;
            b.score = score;
            out.add(b);
        }
        return out;
    }

    /** Середня ймовірність усередині чотирикутника (box_score_fast). */
    private static double fastScore(float[] prob, int w, int h, double[][] c) {
        int[] qx = new int[4], qy = new int[4];
        int xmin = Integer.MAX_VALUE, xmax = -1, ymin = Integer.MAX_VALUE, ymax = -1;
        for (int i = 0; i < 4; i++) {
            qx[i] = (int) c[i][0];
            qy[i] = (int) c[i][1];
            xmin = Math.min(xmin, (int) Math.floor(c[i][0]));
            xmax = Math.max(xmax, (int) Math.ceil(c[i][0]));
            ymin = Math.min(ymin, (int) Math.floor(c[i][1]));
            ymax = Math.max(ymax, (int) Math.ceil(c[i][1]));
        }
        xmin = Math.min(Math.max(xmin, 0), w - 1);
        xmax = Math.min(Math.max(xmax, 0), w - 1);
        ymin = Math.min(Math.max(ymin, 0), h - 1);
        ymax = Math.min(Math.max(ymax, 0), h - 1);
        double sum = 0;
        long cnt = 0;
        for (int y = ymin; y <= ymax; y++)
            for (int x = xmin; x <= xmax; x++)
                if (inside(qx, qy, x, y)) { sum += prob[y * w + x]; cnt++; }
        return cnt == 0 ? 0 : sum / cnt;
    }

    /** Точка у (можливо повернутому) опуклому чотирикутнику, межа включно. */
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

    /** order_points_clockwise з RapidOCR: за x ділимо на ліві/праві, у кожній парі - за y. */
    static Box orderClockwise(double[] x, double[] y) {
        Integer[] idx = {0, 1, 2, 3};
        java.util.Arrays.sort(idx, (a, b) -> Double.compare(x[a], x[b]));
        int l0 = idx[0], l1 = idx[1], r0 = idx[2], r1 = idx[3];
        int tl = y[l0] <= y[l1] ? l0 : l1, bl = tl == l0 ? l1 : l0;
        int tr = y[r0] <= y[r1] ? r0 : r1, br = tr == r0 ? r1 : r0;
        Box b = new Box();
        int[] o = {tl, tr, br, bl};
        for (int i = 0; i < 4; i++) { b.x[i] = x[o[i]]; b.y[i] = y[o[i]]; }
        return b;
    }
}
