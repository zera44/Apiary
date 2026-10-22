package org.apiary.paddle_ocr;

/** Жадібне CTC-декодування виходу читача рядків (ймовірності [T][C], 0 - blank). */
final class Ctc {
    private Ctc() {}

    /** Текст і середня впевненість по символах; [probs] - плоский масив рядка [T*C] з зсувом [off]. */
    static String decode(float[] probs, int off, int t, int c, String[] chars, float[] confOut) {
        StringBuilder sb = new StringBuilder();
        int prev = -1, n = 0;
        double sum = 0;
        for (int i = 0; i < t; i++) {
            int best = 0;
            float bv = -1;
            int base = off + i * c;
            for (int k = 0; k < c; k++) {
                float v = probs[base + k];
                if (v > bv) { bv = v; best = k; }
            }
            if (best != prev && best != 0 && best < chars.length) {
                sb.append(chars[best]);
                sum += bv;
                n++;
            }
            prev = best;
        }
        if (confOut != null) confOut[0] = n == 0 ? 0f : (float) (sum / n);
        return sb.toString();
    }
}
