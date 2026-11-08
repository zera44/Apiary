package org.apiary.paddle_ocr;

import java.util.ArrayList;
import java.util.List;

import org.apiary.paddle_ocr.OcrV2.Frag;
import org.apiary.paddle_ocr.OcrV2.Gray;
import org.apiary.paddle_ocr.OcrV2.Read;
import org.apiary.paddle_ocr.OcrV2.Reader;

/**
 * Рукописні рядки бланка «Товарний чек» (перенесення coursework/fuzzy_v2/hand.py): друкований розпізнавач рукопис
 * не читає, тому рядки таблиці знаходяться за чорнилом між шапкою («Назва та сорт товарів») і рядком «Разом»,
 * а колонки - за шапкою. Лінії таблиці в Python стираються відрізками Хафа (cv2.HoughLinesP, випадковий),
 * тут - довгими горизонтальними й вертикальними відрізками чорнила (кадр уже вирівняний за нахилом чека).
 */
final class OcrHand {
    private OcrHand() {}

    static List<Frag> handRows(List<Frag> fr, Gray g, Reader rd) throws Exception {
        List<Frag> out = new ArrayList<>();
        Frag hd = null;
        for (Frag f : fr) if (OcrPrim.search("(?i)сорт\\s*товар", f.text)) { hd = f; break; }
        if (hd == null) return out;
        double h = hd.h;
        double a = fr.get(0).angle;
        double ca = Math.cos(a), sa = Math.sin(a);
        double yEnd = Double.POSITIVE_INFINITY;
        for (Frag f : fr) {
            if (f.y > hd.y && OcrPrim.search("^[РДP]азом|Сума\\s*$|ПДВ|Пдв", f.text)) yEnd = Math.min(yEnd, f.y);
        }
        yEnd = Double.isInfinite(yEnd) ? hd.y + 12 * h : yEnd - 0.6 * h;
        double xNameEnd = Double.POSITIVE_INFINITY;
        for (Frag f : fr) {
            if (OcrPrim.search("Один", f.text) && Math.abs(f.y - hd.y) < 2 * h) xNameEnd = Math.min(xNameEnd, f.xLeft);
        }
        if (Double.isInfinite(xNameEnd)) xNameEnd = hd.xRight + h;
        double xSum, xEnd;
        Frag sm = null;
        for (Frag f : fr) if (f.text.contains("Сума") && Math.abs(f.y - hd.y) < 2 * h) { sm = f; break; }
        if (sm != null) {
            String t = sm.text;
            int i = t.lastIndexOf("Сума");
            xSum = sm.xLeft + (sm.xRight - sm.xLeft) * i / t.length() - 1.2 * h;
            xEnd = sm.xRight + 1.5 * h;
        } else {
            xSum = xNameEnd + 6 * h;
            xEnd = xNameEnd + 9 * h;
        }
        // кадр координат фрагментів: поворот на -кут на полотні (W+600)x(H+600), фон білий
        int cw = g.w + 600, chh = g.h + 600;
        int x0 = Math.max(0, (int) (hd.xLeft - 2 * h)), x1 = Math.min(cw, (int) xEnd);
        int y0 = Math.max(0, (int) (hd.y + 0.8 * h)), y1 = Math.min(chh, (int) yEnd);
        int rw = x1 - x0, rh = y1 - y0;
        if (rw <= 0 || rh <= 0) return out;
        int[] roi = new int[rw * rh];
        for (int y = 0; y < rh; y++) {
            for (int x = 0; x < rw; x++) {
                double X = x0 + x, Y = y0 + y;
                double sx = X * ca - Y * sa, sy = X * sa + Y * ca;
                roi[y * rw + x] = sx < 0 || sy < 0 || sx > g.w - 1 || sy > g.h - 1 ? 255
                        : (int) Math.round(OcrV2.bilinear(g, sx, sy));
            }
        }
        boolean[] ink = adaptiveInv(roi, rw, rh, 31, 15);
        eraseLines(ink, rw, rh, h);
        ink = open3(ink, rw, rh);
        ink = bigComponents(ink, rw, rh, h);

        // смуги рядків за горизонтальним профілем чорнила
        List<int[]> bands = new ArrayList<>();
        int st = -1;
        for (int y = 0; y <= rh; y++) {
            boolean on = false;
            if (y < rh) {
                int n = 0;
                for (int x = 0; x < rw; x++) if (ink[y * rw + x]) n++;
                on = n > 0.01 * rw;
            }
            if (on && st < 0) st = y;
            if (!on && st >= 0) {
                if (y - st > 0.4 * h) bands.add(new int[] {st, y});
                st = -1;
            }
        }
        for (int[] b : bands) {
            for (int k = 0; k < 2; k++) {
                boolean item = k == 1;
                int xa = (int) Math.max(0, item ? xSum - x0 : 0);
                int xb = (int) Math.min(rw, item ? x1 - x0 : xNameEnd - x0);
                int first = -1, last = -1, cnt = 0;
                for (int x = xa; x < xb; x++) {
                    boolean any = false;
                    for (int y = b[0]; y < b[1] && !any; y++) any = ink[y * rw + x];
                    if (any) { if (first < 0) first = x; last = x; cnt++; }
                }
                if (cnt < 0.5 * h) continue;
                double l = x0 + first, r = x0 + last;
                if (item) { l = x0 + xa; r = x0 + xb; } // уся комірка «Сума»: цифри тонкі, чорнило видно частково
                double yy0 = y0 + b[0], yy1 = y0 + b[1];
                String txt = "[рукопис]";
                if (item) { // число в колонці «Сума» інколи читається
                    Read rr = OcrV2.read(g, OcrPrim.quad(a, l - 10, r + 10, yy0 - 10, yy1 + 10), rd, OcrV2.STRETCH);
                    String dg = rr.text.replaceAll("\\D", "");
                    if (dg.length() >= 2) txt = dg;
                }
                Frag n = fr.get(0).copy();
                n.boxId = 20000 + out.size();
                n.text = txt;
                n.conf = 0.0;
                n.x = (l + r) / 2;
                n.y = (yy0 + yy1) / 2;
                n.w = r - l;
                n.h = yy1 - yy0;
                n.xLeft = l;
                n.xRight = r;
                n.hand = item ? "ITEM" : "NAME";
                out.add(n);
            }
        }
        return out;
    }

    /** cv2.adaptiveThreshold(MEAN_C, THRESH_BINARY_INV): чорнило, якщо піксель <= округлене середнє вікна - C. */
    static boolean[] adaptiveInv(int[] p, int w, int h, int block, int c) {
        int r = block / 2;
        int W = w + 2 * r, H = h + 2 * r;
        long[] s = new long[(W + 1) * (H + 1)];
        for (int y = 0; y < H; y++) {
            int sy = Math.min(h - 1, Math.max(0, y - r));
            long row = 0;
            for (int x = 0; x < W; x++) {
                int sx = Math.min(w - 1, Math.max(0, x - r));
                row += p[sy * w + sx];
                s[(y + 1) * (W + 1) + x + 1] = s[y * (W + 1) + x + 1] + row;
            }
        }
        boolean[] out = new boolean[w * h];
        double area = (double) block * block;
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                long sum = s[(y + block) * (W + 1) + x + block] - s[y * (W + 1) + x + block]
                        - s[(y + block) * (W + 1) + x] + s[y * (W + 1) + x];
                int mean = (int) Math.round(sum / area);
                out[y * w + x] = p[y * w + x] - mean <= -c;
            }
        }
        return out;
    }

    /** Лінії таблиці: відрізки чорнила довжиною від 3h (з розривами до 0,3h) стираються смугою товщиною 7. */
    static void eraseLines(boolean[] bw, int w, int h, double hh) {
        int minLen = (int) (3 * hh), gap = (int) (0.3 * hh);
        boolean[] er = new boolean[w * h];
        for (int y = 0; y < h; y++) {
            int s = -1, e = -1;
            for (int x = 0; x <= w; x++) {
                boolean v = x < w && bw[y * w + x];
                if (v) {
                    if (s < 0 || x - e > gap) { mark(er, w, h, s, e, y, minLen, true); s = x; }
                    e = x;
                }
            }
            mark(er, w, h, s, e, y, minLen, true);
        }
        for (int x = 0; x < w; x++) {
            int s = -1, e = -1;
            for (int y = 0; y < h; y++) {
                if (bw[y * w + x]) {
                    if (s < 0 || y - e > gap) { mark(er, w, h, s, e, x, minLen, false); s = y; }
                    e = y;
                }
            }
            mark(er, w, h, s, e, x, minLen, false);
        }
        for (int i = 0; i < bw.length; i++) if (er[i]) bw[i] = false;
    }

    private static void mark(boolean[] er, int w, int h, int s, int e, int at, int minLen, boolean horiz) {
        if (s < 0 || e - s < minLen) return;
        for (int t = s - 3; t <= e + 3; t++) {
            for (int d = -3; d <= 3; d++) {
                int x = horiz ? t : at + d, y = horiz ? at + d : t;
                if (x >= 0 && y >= 0 && x < w && y < h) er[y * w + x] = true;
            }
        }
    }

    /** Морфологічне відкриття ядром 3x3. */
    static boolean[] open3(boolean[] b, int w, int h) {
        boolean[] e = new boolean[w * h], d = new boolean[w * h];
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                boolean all = true;
                for (int dy = -1; dy <= 1 && all; dy++) {
                    for (int dx = -1; dx <= 1 && all; dx++) {
                        int X = x + dx, Y = y + dy;
                        if (X >= 0 && Y >= 0 && X < w && Y < h && !b[Y * w + X]) all = false;
                    }
                }
                e[y * w + x] = all;
            }
        }
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                boolean any = false;
                for (int dy = -1; dy <= 1 && !any; dy++) {
                    for (int dx = -1; dx <= 1 && !any; dx++) {
                        int X = x + dx, Y = y + dy;
                        if (X >= 0 && Y >= 0 && X < w && Y < h && e[Y * w + X]) any = true;
                    }
                }
                d[y * w + x] = any;
            }
        }
        return d;
    }

    /** Лише компоненти (8-зв'язність) помітного розміру: дрібні залишки й печатка відкидаються. */
    static boolean[] bigComponents(boolean[] b, int w, int h, double hh) {
        int[] lab = new int[w * h];
        boolean[] out = new boolean[w * h];
        int[] stack = new int[w * h];
        List<Integer> members = new ArrayList<>();
        int next = 0;
        for (int i = 0; i < b.length; i++) {
            if (!b[i] || lab[i] != 0) continue;
            next++;
            int sp = 0, area = 0, minX = w, maxX = -1, minY = h, maxY = -1;
            stack[sp++] = i;
            lab[i] = next;
            members.clear();
            while (sp > 0) {
                int p = stack[--sp];
                members.add(p);
                area++;
                int px = p % w, py = p / w;
                minX = Math.min(minX, px); maxX = Math.max(maxX, px);
                minY = Math.min(minY, py); maxY = Math.max(maxY, py);
                for (int dy = -1; dy <= 1; dy++) {
                    for (int dx = -1; dx <= 1; dx++) {
                        int X = px + dx, Y = py + dy;
                        if (X < 0 || Y < 0 || X >= w || Y >= h) continue;
                        int q = Y * w + X;
                        if (b[q] && lab[q] == 0) { lab[q] = next; stack[sp++] = q; }
                    }
                }
            }
            boolean keep = area >= 0.15 * hh * hh / 4 && Math.max(maxX - minX + 1, maxY - minY + 1) >= 0.4 * hh;
            if (keep) for (int p : members) out[p] = true;
        }
        return out;
    }
}
