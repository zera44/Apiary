package org.apiary.paddle_ocr;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.apiary.paddle_ocr.OcrV2.Frag;
import org.apiary.paddle_ocr.OcrV2.Gray;
import org.apiary.paddle_ocr.OcrV2.Quad;
import org.apiary.paddle_ocr.OcrV2.Read;
import org.apiary.paddle_ocr.OcrV2.Reader;

/**
 * Дочитування після [OcrV2] (перенесення coursework/fuzzy_v2/recover.py і hand.py): перечитування невпевнених
 * і «зіпсованих» сум з іншими рамками й розтягненнями, пропущені назви ліворуч від суми, «1x» ліворуч від ціни,
 * рукописні рядки бланка «Товарний чек». Регулярні вирази - як у Python (юнікодні \d, \w, \b).
 */
final class OcrRecover {
    private OcrRecover() {}

    private static final Map<String, Pattern> CACHE = new HashMap<>();

    static Pattern re(String p) {
        synchronized (CACHE) {
            Pattern r = CACHE.get(p);
            if (r == null) { r = Pattern.compile(p, Pattern.UNICODE_CHARACTER_CLASS); CACHE.put(p, r); }
            return r;
        }
    }

    static boolean search(String p, String s) { return re(p).matcher(s).find(); }

    static boolean full(String p, String s) { return re(p).matcher(s).matches(); }

    static boolean match(String p, String s) { return re(p).matcher(s).lookingAt(); }

    static String sub(String p, String repl, String s) { return re(p).matcher(s).replaceAll(repl); }

    static final String MONEY = "(?<![\\d.,])-?\\d{1,6}\\s?[.,]\\s?\\d{2}(?![\\d.,]*\\d)";
    static final String KW_RE = "СУМА|ПДВ|ДО\\s*СПЛАТИ|РАЗОМ|УСЬОГО|ВСЬОГО";
    static final String CLEAN = "\\s*-?\\d{1,6}[.,]\\d{2}\\s*([АБВAB]|грн|ГРН)?\\.?\\s*";
    static final String SUSP = "\\d[.,]\\s\\d{2}(?!\\d)|\\d[.,]{2}\\d|(?<![\\d.,])\\d{3,5}\\s*[гГ][рР]?[нН]|\\d[.,]\\d\\s*[гГ]";

    static String strip(String s) { return s.strip(); }

    static int digits(String s) {
        int n = 0;
        for (int i = 0; i < s.length(); i++) if (Character.isDigit(s.charAt(i))) n++;
        return n;
    }

    static int alpha(String s) {
        int n = 0;
        for (int i = 0; i < s.length(); ) {
            int cp = s.codePointAt(i);
            if (Character.isLetter(cp)) n++;
            i += Character.charCount(cp);
        }
        return n;
    }

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

    static Read read1(Gray g, Quad q, Reader rd, double st) throws Exception {
        return OcrV2.read(g, q, rd, new double[] {st});
    }

    /** kop із recover.py: усе, крім цифр, крапок, ком і мінуса, відкидається. */
    static long kopLoose(String t) {
        String s = t.replaceAll("[^\\d.,-]", "").replace(',', '.');
        return Math.round(Double.parseDouble(s) * 100); // кидає NumberFormatException, як Python ValueError
    }

    static long pyRound(double x) { return (long) Math.rint(x); }

    static long kop(String t) { return pyRound(Double.parseDouble(t.replaceAll("[^\\d.,-]", "").replace(',', '.')) * 100); }

    private static double median(double[] v) {
        double[] s = v.clone();
        Arrays.sort(s);
        int n = s.length;
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2;
    }

    private static double percentile(double[] v, double q) {
        double[] s = v.clone();
        Arrays.sort(s);
        int n = s.length;
        double virt = q / 100 * (n - 1);
        double prev = Math.floor(virt);
        int lo = (int) Math.min(Math.max(prev, 0), n - 1), hi = Math.min(lo + 1, n - 1);
        double gm = virt - prev, x = s[lo], y = s[hi], d = y - x;
        return gm >= 0.5 ? y - d * (1 - gm) : x + d * gm;
    }

    // ------------------------------------------------------------------ reread

    /** Невпевнений фрагмент з цифрами без чистої суми: перечитати тісну рамку з кількома розтягненнями. */
    static void reread(List<Frag> fr, Gray g, Reader rd) throws Exception {
        double a = fr.get(0).angle;
        for (Frag f : fr) {
            String t0 = f.text;
            if (f.conf >= 0.85 || !search("\\d", t0) || search(MONEY, t0)) continue;
            String t = "";
            double cf = 0.0;
            for (double pad : new double[] {0.6, 0.7}) {
                Quad p = quad(a, f.xLeft, f.xRight, f.y - pad * f.h, f.y + pad * f.h);
                for (double st : new double[] {1.5, 1.0, 0.8}) {
                    Read r = read1(g, p, rd, st);
                    String t1 = sub("(\\d[.,])\\s(\\d{2})", "$1$2", r.text);
                    if (r.conf > cf && full("\\s*-?\\d{1,6}[.,]\\d{2}\\s*([АБВAB]|грн|ГРН)?\\.?\\s*", t1)) { t = t1; cf = r.conf; }
                }
            }
            if (cf > f.conf + 0.08) { f.text = t; f.conf = cf; }
        }
    }

    private static final class Cand {
        final double cf, px;
        final String t;
        final double[] bx;

        Cand(double cf, String t, double px, double[] bx) { this.cf = cf; this.t = t; this.px = px; this.bx = bx; }
    }

    /** Порядок кортежів Python (cf, t, px, bx) за спаданням. */
    private static final Comparator<Cand> DESC = (p, q) -> {
        int c = Double.compare(q.cf, p.cf);
        if (c != 0) return c;
        c = q.t.compareTo(p.t);
        if (c != 0) return c;
        c = Double.compare(q.px, p.px);
        if (c != 0) return c;
        for (int i = 0; i < 4; i++) {
            c = Double.compare(q.bx[i], p.bx[i]);
            if (c != 0) return c;
        }
        return 0;
    };

    private static Set<Long> moneyValues(List<Frag> fr) {
        Set<Long> vals = new HashSet<>();
        for (Frag f : fr) {
            Matcher m = re(MONEY).matcher(f.text);
            while (m.find()) {
                try { vals.add(kopLoose(m.group().replace(" ", ""))); } catch (NumberFormatException ignored) {}
            }
        }
        return vals;
    }

    /** Друге перечитування з кількома рамками й розтягненнями; нове прочитання приймається, лише якщо воно чисте й узгоджене з чеком. */
    static void reread2(List<Frag> fr, Gray g, Reader rd) throws Exception {
        double a = fr.get(0).angle;
        Set<Long> vals = moneyValues(fr);
        java.util.function.LongPredicate consistent = v -> {
            if (v <= 0) return false;
            for (long u : vals) if (u > 0 && Math.abs(v - u) <= 1) return true;
            for (long u : vals) for (int r : new int[] {20, 7}) if (Math.abs(v - u * (double) r / (100 + r)) <= 1.5) return true;
            return false;
        };
        double xrMax = Double.NEGATIVE_INFINITY;
        for (Frag q : fr) xrMax = Math.max(xrMax, q.xRight);
        for (Frag f : fr) {
            String t0 = f.text;
            double h = f.h;
            boolean degen = f.xRight - f.xLeft < 0.6 * h;
            boolean clean0 = full(CLEAN, t0);
            if (!search("\\d", t0) && !(degen && f.conf < 0.9)) continue;
            if (!(f.conf < 0.9 || search(SUSP, t0) || (clean0 && f.conf < 0.93))) continue;
            double[] pxs = degen ? new double[] {0.5, 0.8, 1.0, 1.3, 1.6} : new double[] {0.0, 0.5};
            List<Cand> best = new ArrayList<>();
            List<java.util.concurrent.Callable<Cand>> jobs = new ArrayList<>(); // незалежні читання - паралельно, порядок збережено
            boolean cut = !degen && search("\\d[.,]\\s\\d{2}(?!\\d)", t0);
            if (cut) { // рамка відрізала початок великого числа - ширше ліворуч
                for (double L : new double[] {1.5, 2.0, 2.5, 3.0})
                    for (double pad : new double[] {0.6, 0.8, 1.0}) {
                        double x1 = f.xLeft - L * h, x2 = f.xRight, y1 = f.y - pad * h, y2 = f.y + pad * h;
                        Quad p = quad(a, x1, x2, y1, y2);
                        for (double st : new double[] {1.0, 0.8}) {
                            final double fL = L;
                            jobs.add(() -> {
                                Read r = read1(g, p, rd, st);
                                return new Cand(r.conf, sub("(\\d[.,])\\s(\\d{2})", "$1$2", strip(r.text)), fL, new double[] {x1, x2, y1, y2});
                            });
                        }
                    }
            }
            for (double px : pxs)
                for (double pad : degen ? new double[] {0.5, 0.6, 0.8, 1.0} : new double[] {0.6, 0.8, 1.0}) {
                    double x1, x2;
                    if (degen) { x1 = f.x - px * h; x2 = f.x + px * h; } else { x1 = f.xLeft - px * h; x2 = f.xRight + px * h; }
                    double y1 = f.y - pad * h, y2 = f.y + pad * h;
                    Quad p = quad(a, x1, x2, y1, y2);
                    for (double st : new double[] {1.5, 1.0, 0.8}) {
                        final double fpx = px;
                        jobs.add(() -> {
                            Read r = read1(g, p, rd, st);
                            return new Cand(r.conf, sub("(\\d[.,])\\s(\\d{2})", "$1$2", strip(r.text)), fpx, new double[] {x1, x2, y1, y2});
                        });
                    }
                }
            best.addAll(rd.parallel(jobs));
            best.sort(DESC);
            if (cut) { // спершу прочитання, узгоджені з іншими сумами чека
                Matcher mv = re("\\d{1,6}[.,]\\s\\d{2}").matcher(t0);
                mv.find();
                long v0 = kopLoose(mv.group().replace(" ", ""));
                List<Cand> ok = new ArrayList<>(), no = new ArrayList<>();
                for (Cand b : best) {
                    boolean good = false;
                    if (full(CLEAN, b.t)) {
                        Matcher m = re("\\s*-?\\d{1,6}[.,]\\d{2}").matcher(b.t);
                        m.lookingAt();
                        long v = kopLoose(m.group());
                        good = v != v0 && consistent.test(v);
                    }
                    (good ? ok : no).add(b);
                }
                best = new ArrayList<>(ok);
                best.addAll(no);
            }
            boolean edge = f.xRight >= 0.97 * xrMax;
            if (edge) for (Frag q : fr) if (q != f && Math.abs(q.y - f.y) < 0.5 * h && q.xLeft > f.xRight) { edge = false; break; }
            boolean tax0 = search("[АБВГДABд]\\s*$", t0);
            Cand acc = null;
            String accText = null;
            for (Cand b : best) {
                String t = b.t;
                double cf = b.cf;
                if (t0.contains("%") && !t.contains("%")) continue;
                if (tax0 && !search("[АБВГДABд]\\s*$", t)) continue;
                if (full(CLEAN, t)) {
                    Matcher m = re("\\s*-?\\d{1,6}[.,]\\d{2}").matcher(t);
                    m.lookingAt();
                    long v = kopLoose(m.group());
                    if (clean0) {
                        Matcher m0 = re("\\s*-?\\d{1,6}[.,]\\d{2}").matcher(t0);
                        m0.lookingAt();
                        if (!strip(t).equals(strip(t0)) && cf >= 0.97 && kopLoose(m0.group()) != v && consistent.test(v)) { acc = b; accText = t; }
                    } else if (cf >= 0.85 && (consistent.test(v) || (cf >= Math.max(0.9, f.conf + 0.05) && b.px == 0 && digits(t0) >= 2
                            && digits(t) >= digits(t0) - 1))) {
                        acc = b; accText = t;
                    }
                } else if ((full("\\s*\\d\\s+\\d{2,3}\\s*", t0) && full("\\s*\\d{2,3}\\s*", t) && cf >= Math.max(0.93, f.conf + 0.1)
                        && t0.replaceAll("\\s", "").endsWith(strip(t)) && edge && f.y > 0.08 * f.imgH)
                        || (full("\\s*(\\d)\\1\\s*", t0) && full("\\s*\\d\\s*", t) && strip(t).equals(strip(t0).substring(0, 1))
                        && cf >= Math.max(0.95, f.conf + 0.15))) {
                    acc = b; accText = t;
                } else if (full("\\s*ПДВ\\s*[АБВГДAB]?\\s*=?\\s*(20|7|14|0)[.,]00\\s*%\\S?\\s*", t.toUpperCase()) && cf >= 0.9 && f.conf < 0.85
                        && !search(KW_RE, t0.toUpperCase()) && !t0.contains("%")) {
                    acc = b; accText = t.replaceAll("%.*", "%");
                } else if ((!search("\\d", t0) || f.conf < 0.5 || search("ПДВ.*\\d{1,2}[.,]\\d{2}\\s*%", t.toUpperCase()))
                        && search(KW_RE, t.toUpperCase()) && !search(KW_RE, t0.toUpperCase()) && cf >= 0.95 && f.conf < 0.85) {
                    acc = b; accText = t;
                }
                if (acc != null) break;
            }
            if (acc != null) {
                f.text = accText;
                f.conf = acc.cf;
                if (degen) degenBox(f, g, a);
            }
        }
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

    /** Сума позиції, прочитана як «ціна× 1=»: перечитати без множення. */
    static void reread3(List<Frag> fr, Gray g, Reader rd) throws Exception {
        double a = fr.get(0).angle;
        for (Frag f : fr) {
            String t0 = f.text;
            double h = f.h;
            Matcher m = re("\\s*(\\d{1,6}[.,]\\d{2})\\s*[×xхХX]\\s*1?\\s*=?\\s*").matcher(t0);
            if (!m.matches()) continue;
            String v = m.group(1);
            boolean right = false, leftSame = false;
            for (Frag q : fr) {
                if (q == f || Math.abs(q.y - f.y) >= 0.5 * h) continue;
                if (q.xLeft > f.xRight) right = true;
                if (q.xRight < f.xLeft && search(Pattern.quote(v) + "\\s*[×xхХX]", q.text)) leftSame = true;
            }
            if (right || !leftSame) continue;
            List<Object[]> best = new ArrayList<>(); // cf, len, t
            for (double px : new double[] {-0.5, -0.3, 0.0})
                for (double pad : new double[] {0.5, 0.6, 0.8}) {
                    Quad p = quad(a, f.xLeft, f.xRight + px * h, f.y - pad * h, f.y + pad * h);
                    for (double st : new double[] {1.5, 1.0, 0.8}) {
                        Read r = read1(g, p, rd, st);
                        if (full("\\s*" + Pattern.quote(v) + "\\s*(-\\s*[АA]?)?\\s*", r.text))
                            best.add(new Object[] {r.conf, strip(r.text).length(), strip(r.text)});
                    }
                }
            Comparator<Object[]> desc = (p, q) -> {
                int c = Double.compare((Double) q[0], (Double) p[0]);
                if (c != 0) return c;
                c = Integer.compare((Integer) q[1], (Integer) p[1]);
                if (c != 0) return c;
                return ((String) q[2]).compareTo((String) p[2]);
            };
            best.sort(desc);
            if (!best.isEmpty() && (Double) best.get(0)[0] >= 0.9) {
                List<Object[]> ok = new ArrayList<>();
                for (Object[] b : best) if ((Double) b[0] >= 0.9) ok.add(b);
                ok.sort((p, q) -> {
                    int c = Integer.compare((Integer) q[1], (Integer) p[1]);
                    return c != 0 ? c : Double.compare((Double) q[0], (Double) p[0]);
                });
                f.text = (String) ok.get(0)[2];
                f.conf = (Double) best.get(0)[0];
            }
        }
    }

    /** «1 х 34,00» у рамці, куди влазить лише «34,00»: префікс «N х» дописано з рисок над числом. */
    static void stripQty(List<Frag> fr) {
        for (Frag f : fr) {
            String t0 = f.text;
            Matcher m = re("\\s*\\d{1,3}\\s*[хxХX×]\\s*(\\d{1,5}[.,]\\d{2})\\s*").matcher(t0);
            if (m.matches() && (f.xRight - f.xLeft) / (f.h * strip(t0).length()) < 0.25) f.text = m.group(1);
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < fr.size(); i++) { if (i > 0) sb.append(" | "); sb.append(fr.get(i).text); }
        String allt = sb.toString();
        for (Frag f : fr) {
            String t0 = f.text;
            Matcher m = re("\\s*1\\s+(\\d{1,5}[.,]\\d{2})\\s*").matcher(t0);
            if (m.matches() && f.conf < 0.9
                    && search("(?<![\\d.,])(?<!1 )" + Pattern.quote(m.group(1)) + "(?!\\d)", allt.replace(t0, ""))) {
                f.xLeft = f.xRight - (f.xRight - f.xLeft) * m.group(1).length() / strip(t0).length();
                f.x = (f.xLeft + f.xRight) / 2;
                f.text = m.group(1);
            }
        }
    }

    /** Ціна під пунктирною лінією: риска над числом читається як «1» - рамка звужується. */
    static void reread4(List<Frag> fr, Gray g, Reader rd) throws Exception {
        double a = fr.get(0).angle;
        Set<Long> vals = moneyValues(fr);
        for (Frag f : fr) {
            String t0 = f.text;
            double h = f.h;
            if (f.conf >= 0.9 || !full("\\s*1\\s*[хxХX×]?\\s*[\\d.,]*\\d[\\d.,]*\\s*", t0) || full(CLEAN, t0)) continue;
            double bc = -1;
            String bt = null;
            for (double dy : new double[] {0.0, 0.1, 0.2})
                for (double pad : new double[] {0.4, 0.5}) {
                    Quad p = quad(a, f.xLeft + 0.3 * h, f.xRight + 0.2 * h, f.y + (dy - pad) * h, f.y + (dy + pad) * h);
                    for (double st : new double[] {1.5, 1.0}) {
                        Read r = read1(g, p, rd, st);
                        String t = strip(r.text);
                        if (full("\\d{1,5}[.,]\\d{2}", t) && r.conf >= 0.93 && kopLoose(t) > 0 && vals.contains(kopLoose(t))) {
                            if (bt == null || r.conf > bc || (r.conf == bc && t.compareTo(bt) > 0)) { bc = r.conf; bt = t; }
                        }
                    }
                }
            if (bt != null) { f.text = bt; f.conf = bc; }
        }
    }

    /** «1x» ліворуч від ціни, які детектор пропустив (лише в чеку, де хоч один такий уже знайдено). */
    static List<Frag> qtyMarks(List<Frag> fr, Gray g, Reader rd) throws Exception {
        double a = fr.get(0).angle;
        String mkRe = "\\s*\\d{1,2}\\s*[xхХX×]\\s*";
        List<Frag> mk = new ArrayList<>();
        for (Frag f : fr) if (full(mkRe, f.text)) mk.add(f);
        List<Frag> add = new ArrayList<>();
        if (mk.isEmpty()) return add;
        double[] mxl = new double[mk.size()];
        for (int i = 0; i < mxl.length; i++) mxl[i] = mk.get(i).xLeft;
        double xl = median(mxl);
        double[] xs = new double[fr.size()];
        for (int i = 0; i < xs.length; i++) xs[i] = fr.get(i).x;
        double xmid = median(xs);
        for (Frag p : fr) {
            if (!full("\\s*\\d{1,5}[.,]\\d{2}\\s*", p.text) || p.x < xmid) continue;
            double h = p.h;
            boolean has = false;
            List<Frag> all = new ArrayList<>(fr);
            all.addAll(add);
            for (Frag q : all)
                if (Math.abs(q.y - p.y) < 1.0 * h && q.xLeft < xl + 2 * h && q.xRight > xl && full(mkRe, q.text)) { has = true; break; }
            if (has) continue;
            String bt = null;
            double bc = 0, bx1 = 0, bx2 = 0, byc = 0;
            for (double dy : new double[] {-0.4, -0.2, 0.0, 0.2, 0.4}) {
                double yc = p.y + dy * h;
                boolean busy = false;
                for (Frag q : fr) if (Math.abs(q.y - yc) < 0.5 * h && q.xLeft < xl + 1.7 * h && q.xRight > xl) { busy = true; break; }
                if (busy) continue;
                for (double pad : new double[] {0.5, 0.6}) {
                    double x1 = xl - 0.3 * h, x2 = xl + 1.7 * h;
                    Quad P = quad(a, x1, x2, yc - pad * h, yc + pad * h);
                    for (double st : new double[] {1.5, 1.0}) {
                        Read r = read1(g, P, rd, st);
                        if (full(mkRe, r.text) && r.conf >= 0.9 && (bt == null || r.conf > bc)) {
                            bt = strip(r.text); bc = r.conf; bx1 = x1; bx2 = x2; byc = yc;
                        }
                    }
                }
            }
            if (bt != null) {
                Frag n = p.copy();
                n.boxId = 20000 + add.size();
                n.text = bt;
                n.conf = bc;
                n.x = (bx1 + bx2) / 2;
                n.w = bx2 - bx1;
                n.xLeft = bx1 + 0.3 * h;
                n.xRight = bx1 + 0.3 * h + 1.2 * h;
                n.y = byc;
                n.recovered = true;
                add.add(n);
            }
        }
        return add;
    }

    private static Set<String> stems(String u) {
        Set<String> s = new HashSet<>();
        Matcher m = re("[^\\W\\d_]{5,}").matcher(u);
        while (m.find()) s.add(m.group().substring(0, 5).toUpperCase());
        return s;
    }

    /** Пропущена назва: праворуч є сума, а ліворуч у тому самому рядку детектор не знайшов жодної рамки. */
    static List<Frag> recover(List<Frag> fr, Gray g, Reader rd) throws Exception {
        double a = fr.get(0).angle;
        double[] xl = new double[fr.size()], xs = new double[fr.size()];
        for (int i = 0; i < xl.length; i++) { xl[i] = fr.get(i).xLeft; xs[i] = fr.get(i).x; }
        double X0 = percentile(xl, 5), xmid = median(xs);
        List<Frag> add = new ArrayList<>();
        for (Frag f : fr) {
            if (!search(MONEY, f.text) || f.x < xmid) continue;
            double h = f.h;
            boolean left = false;
            for (Frag q : fr)
                if (q != f && alpha(q.text) >= 2 && q.xRight < f.xLeft + 0.2 * h && Math.abs(q.y - f.y) < 0.45 * h) { left = true; break; }
            if (left || f.xLeft - X0 < 4 * h) continue;
            double x1 = X0 - 0.3 * h, x2 = f.xLeft - 0.3 * h;
            double cover = 0;
            for (Frag q : fr)
                if (q != f && alpha(q.text) > 0 && Math.abs(q.y - f.y) < 0.45 * h)
                    cover += Math.max(0, Math.min(q.xRight, f.xLeft) - Math.max(q.xLeft, X0));
            if (cover > 0.3 * (f.xLeft - X0)) continue;
            Read r = OcrV2.read(g, quad(a, x1, x2, f.y - 0.55 * h, f.y + 0.55 * h), rd, OcrV2.STRETCH);
            String t = strip(r.text);
            if (alpha(t) < 4 || r.conf < 0.85 || search(MONEY + "(?!\\s*%)", t)) continue;
            Set<String> st = stems(t), near = new HashSet<>();
            for (Frag q : fr) if (Math.abs(q.y - f.y) < 1.6 * h) near.addAll(stems(q.text));
            st.retainAll(near);
            if (!st.isEmpty()) continue;
            Frag n = f.copy();
            n.boxId = 10000 + add.size();
            n.text = t;
            n.conf = r.conf;
            n.x = (x1 + x2) / 2;
            n.w = x2 - x1;
            n.xLeft = x1;
            n.xRight = x2;
            n.recovered = true;
            add.add(n);
        }
        return add;
    }

    /** Розпізнавання з дочитуванням: mode "ocr" - лише OcrV2, "all" - з дочитуванням. */
    static OcrV2.Result recognize(Gray g0, Reader rd, String mode) throws Exception {
        OcrV2.Result res = OcrV2.run(g0, rd);
        if (!"all".equals(mode) || res.frags.isEmpty()) return res;
        List<Frag> fr = res.frags;
        Gray g = res.g;
        reread(fr, g, rd);
        reread2(fr, g, rd);
        reread3(fr, g, rd);
        reread4(fr, g, rd);
        stripQty(fr);
        for (Frag f : fr) if (match("\\s*-\\s*-\\s*\\d", f.text)) f.text = sub("^\\s*-\\s*-", "-", f.text);
        List<Frag> add = recover(fr, g, rd);
        add.addAll(OcrHand.handRows(fr, g, rd));
        add.addAll(qtyMarks(fr, g, rd));
        fr.addAll(add);
        return res;
    }
}
