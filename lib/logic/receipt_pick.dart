/// Вибір між двома прочитаннями одного чека: нечітка розмітка ([FzReceipt]) і розбір тексту ([parseReceipt]).
///
/// Чек сам себе перевіряє: сума позицій має дорівнювати сумі, надрукованій на чеку. Розмітка лишається основною.
/// Розбір тексту береться лише тоді, коли розмітка цієї рівності не дає, а розбір - дає
/// ([receiptSelfVerified], суворо, без підгонки). Якщо не підтверджено ніде - розмітка, а коли вона порожня, - розбір.
library;

import 'fz2/receipt_rows.dart';
import 'receipt_parser.dart';

/// Прочитаний чек: позиції, сума чека, чи сума позицій збіглась із нею і звідки це взято.
class ReceiptReading {
  final List<ReceiptRow> rows;
  final double? declared;

  /// Сума позицій дорівнює сумі чека (ні гроші виведені з підсумку, ні підсумок із позицій).
  final bool verified;

  /// 'fz' - розмітка, 'text' - розбір тексту.
  final String source;

  const ReceiptReading(this.rows, this.declared, this.verified, this.source);
}

List<ReceiptRow> _fzRows(FzReceipt fz) =>
    [for (final r in fz.rows) ReceiptRow(name: r.name, qty: r.qty, unit: r.unit, price: r.price)];

bool _sumsMatch(List<ReceiptRow> rows, double? declared) {
  if (rows.isEmpty || declared == null || declared < 1) return false;
  final sum = rows.fold<double>(0, (s, r) => s + r.total);
  return (sum - declared).abs() <= 0.02;
}

/// [fz] - розмітка (null - не вийшла), [texts] - тексти чека, зібрані по-різному (перший - основний).
ReceiptReading pickReading(FzReceipt? fz, List<String> texts) {
  final fzRows = fz == null ? <ReceiptRow>[] : _fzRows(fz);
  if (fz != null && _sumsMatch(fzRows, fz.total)) return ReceiptReading(fzRows, fz.total, true, 'fz');
  for (final t in texts) {
    if (receiptSelfVerified(t)) {
      return ReceiptReading(parseReceipt(t, fillMissing: false), receiptDeclaredTotal(t), true, 'text');
    }
  }
  if (fz != null && (fzRows.isNotEmpty || fz.total != null)) return ReceiptReading(fzRows, fz.total, false, 'fz');
  if (texts.isNotEmpty) {
    final t = texts.first;
    return ReceiptReading(parseReceipt(t, fillMissing: false), receiptDeclaredTotal(t), false, 'text');
  }
  return const ReceiptReading([], null, false, 'text');
}
