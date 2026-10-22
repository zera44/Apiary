# paddle_ocr_flutter

Офлайн-розпізнавання тексту чеків для «Моя пасіка» (лише Android): PaddleOCR PP-OCR в ONNX Runtime.

Конвеєр (`android/src/main/java/org/apiary/paddle_ocr/`):
1. `Img` - фото -> сіре (канал з найбільшим контрастом) -> тензор детектора;
2. детектор рядків DB (`DbPost`: маска, зв'язні області, обертові прямокутники, розширення) - `assets/ocr/det.onnx` (PP-OCRv6 small);
3. `Img.warp` - вирізання кожного рядка; читач CTC (`Ctc`) - `assets/ocr/rec.onnx` (PP-OCRv5 для східнослов'янських мов, донавчений на чеках) + `assets/ocr/dict.txt`;
4. `OcrPipeline` - добір повороту фото, збирання рамок у рядки (назва й ціна на одній висоті - один рядок).

Логіка без Android (все, крім `PaddleOcrPlugin`) перевіряється на ПК: `tool/ParityMain.java` запускає справжній код на фото, а моделі виконує `tool/ort_runner.py`:

    javac -d /tmp/jc android/src/main/java/org/apiary/paddle_ocr/{Geom,DbPost,Ctc,Img,OcrPipeline}.java tool/ParityMain.java
    java -Dstdout.encoding=UTF-8 -cp /tmp/jc ParityMain det.onnx rec.onnx assets/ocr/dict.txt чек.jpg

Важливо: читач запускається по ОДНОМУ рядку - у пакеті з відступами (padding) модель обрізає останні символи.
