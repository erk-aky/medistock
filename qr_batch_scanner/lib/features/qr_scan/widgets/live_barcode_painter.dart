import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

// Canlı taramada kameradaki karekodların üstüne renkli kutu, okunmuşlara çarpı çizer
class LiveBarcodePainter extends CustomPainter {
  final List<Barcode> barcodes;
  final Size? imageSize;
  final Map<String, Color> barcodeColors;
  final Set<String> scannedBarcodes;
  final BuildContext context;

  LiveBarcodePainter({
    required this.barcodes,
    this.imageSize,
    required this.barcodeColors,
    required this.scannedBarcodes,
    required this.context,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize == null || barcodes.isEmpty) return;

    // 1. Dinamik Ölçekleme Hesabı
    // Kamera görüntüsünün ekranı (BoxFit.cover gibi) tam doldurması için gereken oran.
    // Artık inputWidth/inputHeight ayrımı yok, imageSize neyse o kabul edilir.
    final double scaleX = size.width / imageSize!.width;
    final double scaleY = size.height / imageSize!.height;

    // Görüntüyü ekranın en dar kenarına göre büyütüp boşluk bırakmamak için 'max' kullanıyoruz.
    final double scale = scaleX > scaleY ? scaleX : scaleY;

    // 2. Ortalama (Centering) Hesabı
    // Görüntü ekrandan büyükse (cover olduğu için taşacaktır),
    // koordinatların kaymaması için bu taşma miktarını (offset) bulmalıyız.
    final double offsetX = (size.width - imageSize!.width * scale) / 2;
    final double offsetY = (size.height - imageSize!.height * scale) / 2;

    for (final barcode in barcodes) {
      final corners = barcode.corners;
      final rawValue = barcode.rawValue;
      if (corners == null || rawValue == null) continue;

      Color baseColor = barcodeColors[rawValue] ?? Colors.greenAccent;

      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = baseColor.withOpacity(0.3);

      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..color = baseColor;

      // 3. Koordinat Dönüşümü
      // Kameranın (0,0) noktası ile ekranın (0,0) noktasını scale ve offset ile eşitliyoruz.
      final List<Offset> transformedCorners = corners.map((corner) {
        return Offset(
          (corner.dx * scale) + offsetX,
          (corner.dy * scale) + offsetY,
        );
      }).toList();

      final path = Path()..addPolygon(transformedCorners, true);

      canvas.drawPath(path, paint);
      canvas.drawPath(path, borderPaint);

      // --- Zaten taranmışsa çarpı (X) işareti çiz ---
      if (scannedBarcodes.contains(rawValue) && transformedCorners.length >= 4) {
        final crossPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..color = baseColor;

        canvas.drawLine(transformedCorners[0], transformedCorners[2], crossPaint);
        canvas.drawLine(transformedCorners[1], transformedCorners[3], crossPaint);
      }
    }
  }

  @override
  bool shouldRepaint(LiveBarcodePainter oldDelegate) => true;
}
