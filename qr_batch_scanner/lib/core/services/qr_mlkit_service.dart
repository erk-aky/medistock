import 'dart:io';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class QrMlkitService {
  final BarcodeScanner _scanner = BarcodeScanner(
    formats: [BarcodeFormat.qrCode],
  );

  /// Fotoğraftan QR'ları okur (bir resimde birden fazla QR destekler)
  Future<List<String>> scanQrFromImage(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final List<Barcode> barcodes = await _scanner.processImage(inputImage);

    final results = <String>[];
    for (final barcode in barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        results.add(value);
      }
    }

    // Duplicate'ları temizle
    return results.toSet().toList();
  }

  Future<void> dispose() async {
    await _scanner.close();
  }
}
