package org.apiary.paddle_ocr;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * Розпізнавання чека: детектор рядків (DB) -> вирізання рядків -> читач (CTC) -> збирання рядків тексту.
 * Моделі запускає [Runner] (ONNX Runtime на телефоні); сама логіка без Android і перевіряється на ПК.
 */
final class OcrPipeline {
    private OcrPipeline() {}

    interface Runner {
        /** Карта ймовірностей детектора h*w для входу CHW (1,3,h,w). */
        float[] det(float[] chw, int h, int w) throws Exception;

        /** Ймовірності читача [n][t][c] для входу (n,3,48,w); t і c - у outTC. */
        float[] rec(float[] nchw, int n, int w, int[] outTC) throws Exception;
    }

    static final class Row {
        String text;
        float conf;
        DbPost.Box box;
    }

    static final class Result {
        final List<String> lines = new ArrayList<>();
        final List<Row> rows = new ArrayList<>();
        int rotation; // 0, 90, 180, 270 за годинниковою
        float meanConf;
    }

    static final int DET_MIN_SIDE = 736, DET_MAX_SIDE = 2400, REC_BATCH = 1;

    static int round32(double v) { return Math.max(32, (int) (Math.round(v / 32.0) * 32)); }

    /** Один прохід: детекція + читання на сірому зображенні [g] розміром w x h. */
    static List<Row> pass(byte[] g, int w, int h, Runner run, String[] chars) throws Exception {
        double r = 1;
        int mn = Math.min(w, h), mx = Math.max(w, h);
        if (mn < DET_MIN_SIDE) r = (double) DET_MIN_SIDE / mn;
        if (mx * r > DET_MAX_SIDE) r = (double) DET_MAX_SIDE / mx;
        int rw = round32(w * r), rh = round32(h * r);
        float[] prob = run.det(Img.detTensor(g, w, h, rw, rh), rh, rw);
        List<DbPost.Box> boxes = DbPost.boxes(prob, rw, rh, w, h, 0.3f, 0.5f, 1.6, true, 1000);
        List<byte[]> crops = new ArrayList<>();
        List<int[]> dims = new ArrayList<>();
        List<DbPost.Box> kept = new ArrayList<>();
        for (DbPost.Box b : boxes) {
            int[] wh = new int[2];
            byte[] c = Img.warp(g, w, h, b, wh);
            if (wh[0] < 4 || wh[1] < 4) continue;
            crops.add(c);
            dims.add(wh);
            kept.add(b);
        }
        int n = crops.size();
        Integer[] order = new Integer[n];
        for (int i = 0; i < n; i++) order[i] = i;
        Arrays.sort(order, Comparator.comparingInt(i -> Img.recWidth(dims.get(i)[0], dims.get(i)[1])));
        Row[] rows = new Row[n];
        for (int s = 0; s < n; s += REC_BATCH) {
            int e = Math.min(n, s + REC_BATCH), cnt = e - s, maxW = 0;
            for (int k = s; k < e; k++) maxW = Math.max(maxW, Img.recWidth(dims.get(order[k])[0], dims.get(order[k])[1]));
            float[] t = new float[cnt * 3 * Img.REC_H * maxW];
            Arrays.fill(t, 1f);
            for (int k = s; k < e; k++) {
                int i = order[k];
                Img.recTensor(crops.get(i), dims.get(i)[0], dims.get(i)[1], Img.recWidth(dims.get(i)[0], dims.get(i)[1]), t, k - s, cnt, maxW);
            }
            int[] tc = new int[2];
            float[] out = run.rec(t, cnt, maxW, tc);
            for (int k = s; k < e; k++) {
                int i = order[k];
                int nw = Img.recWidth(dims.get(i)[0], dims.get(i)[1]);
                int valid = Math.min(tc[0], (nw + 7) / 8 + 1);
                float[] cf = new float[1];
                Row row = new Row();
                row.text = Ctc.decode(out, (k - s) * tc[0] * tc[1], valid, tc[1], chars, cf).trim();
                row.conf = cf[0];
                row.box = kept.get(i);
                rows[i] = row;
            }
        }
        List<Row> res = new ArrayList<>();
        for (Row row : rows) if (row != null && !row.text.isEmpty()) res.add(row);
        return res;
    }

    static float meanConf(List<Row> rows) {
        double s = 0;
        int n = 0;
        for (Row r : rows) { s += (double) r.conf * r.text.length(); n += r.text.length(); }
        return n == 0 ? 0 : (float) (s / n);
    }

    /** Чек на зображенні [g] (w x h): сам добирає поворот (якщо фото боком чи догори дриґом). */
    static Result run(byte[] g, int w, int h, Runner run, String[] chars) throws Exception {
        List<Row> rows = pass(g, w, h, run, chars);
        int rotation = 0;
        // фото боком: більшість рамок вищі за ширину -> повернути на 90°
        int tall = 0;
        for (Row r : rows) if (r.box.height() > r.box.width()) tall++;
        byte[] cur = g;
        int cw = w, ch = h;
        if (!rows.isEmpty() && tall * 2 > rows.size()) {
            byte[] r90 = Img.rotate90cw(g, w, h);
            List<Row> a = pass(r90, h, w, run, chars);
            byte[] r270 = Img.rotate180(r90, h, w);
            List<Row> b = pass(r270, h, w, run, chars);
            if (meanConf(a) >= meanConf(b)) { rows = a; rotation = 90; cur = r90; } else { rows = b; rotation = 270; cur = r270; }
            cw = h; ch = w;
        }
        if (meanConf(rows) < 0.6f) { // можливо догори дриґом
            byte[] f = Img.rotate180(cur, cw, ch);
            List<Row> b = pass(f, cw, ch, run, chars);
            if (meanConf(b) > meanConf(rows) + 0.05f) { rows = b; rotation = (rotation + 180) % 360; }
        }
        Result res = new Result();
        res.rotation = rotation;
        res.meanConf = meanConf(rows);
        res.rows.addAll(rows);
        res.lines.addAll(toLines(rows));
        return res;
    }

    /** Рамка [i] стоїть НАД/ПІД однією з рамок рядка [line] (їхні проміжки по горизонталі перекриваються): це два різні рядки, а не частини одного. */
    private static boolean stacked(List<Integer> line, int i, double[] x, List<Row> rows) {
        double wi = rows.get(i).box.width();
        for (int j : line) {
            double wj = rows.get(j).box.width();
            double ov = Math.min(x[i] + wi / 2, x[j] + wj / 2) - Math.max(x[i] - wi / 2, x[j] - wj / 2);
            if (ov > 0.3 * Math.min(wi, wj)) return true;
        }
        return false;
    }

    /** Рамки -> рядки тексту: загальний нахил фото знімається, рамки на одній висоті зливаються (назва + ціна). */
    static List<String> toLines(List<Row> rows) {
        List<Double> ang = new ArrayList<>();
        for (Row r : rows) if (r.box.width() > 3 * r.box.height()) ang.add(r.box.angle());
        double a = 0;
        if (!ang.isEmpty()) { Collections.sort(ang); a = ang.get(ang.size() / 2); }
        final double cos = Math.cos(-a), sin = Math.sin(-a);
        final int n = rows.size();
        double[] x = new double[n], y = new double[n], hh = new double[n];
        Integer[] idx = new Integer[n];
        for (int i = 0; i < n; i++) {
            DbPost.Box b = rows.get(i).box;
            x[i] = b.centerX() * cos - b.centerY() * sin;
            y[i] = b.centerX() * sin + b.centerY() * cos;
            hh[i] = b.height();
            idx[i] = i;
        }
        Arrays.sort(idx, (p, q) -> Double.compare(y[p], y[q]));
        List<List<Integer>> lines = new ArrayList<>();
        double top = 0, bot = 0;
        for (int k = 0; k < n; k++) {
            int i = idx[k];
            double t = y[i] - hh[i] / 2, bt = y[i] + hh[i] / 2;
            if (!lines.isEmpty()) {
                double ov = Math.min(bot, bt) - Math.max(top, t);
                if (ov >= 0.5 * Math.min(bot - top, bt - t) && !stacked(lines.get(lines.size() - 1), i, x, rows)) {
                    lines.get(lines.size() - 1).add(i);
                    top = Math.min(top, t);
                    bot = Math.max(bot, bt);
                    continue;
                }
            }
            List<Integer> l = new ArrayList<>();
            l.add(i);
            lines.add(l);
            top = t;
            bot = bt;
        }
        List<String> out = new ArrayList<>();
        for (List<Integer> l : lines) {
            Collections.sort(l, (p, q) -> Double.compare(x[p], x[q]));
            StringBuilder sb = new StringBuilder();
            for (int m = 0; m < l.size(); m++) {
                int i = l.get(m);
                if (m > 0) {
                    int pi = l.get(m - 1);
                    double gap = (x[i] - rows.get(i).box.width() / 2) - (x[pi] + rows.get(pi).box.width() / 2);
                    sb.append(gap > 4 * hh[i] ? "   " : " ");
                }
                sb.append(rows.get(i).text);
            }
            out.add(sb.toString());
        }
        return out;
    }
}
