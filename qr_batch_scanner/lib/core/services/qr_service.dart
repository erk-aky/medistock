import 'dart:io';
import '../constants/api_constants.dart';
import '../models/qr_lookup_result.dart';
import '../network/api_client.dart';

class QrService {
  final ApiClient _api;

  QrService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  /// FOTOĞRAF GÖNDER → BACKEND → SADECE JSON (KOORDİNAT + DB VERİLERİ)
  Future<QrLookupResponse> uploadQrImage(File imageFile) async {
    if (!imageFile.existsSync()) {
      throw Exception('Resim dosyası bulunamadı');
    }

    print('---------- 🚀 QR API ISTEGI (AKILLI PARÇALAMA MODU) ----------');
    print('Hedef Adres: ${_api.uri(ApiConstants.qrLookup)}');
    print('Dosya Yolu: ${imageFile.path}');
    print('--------------------------------------');

    try {
      // Backend artık parçalama ve DB sorgusu yaptığı için timeout'u 30 saniyeye çektim (ideal süre)
      final decodedData = await _api.postFile(
        ApiConstants.qrLookup,
        'image',
        imageFile.path,
        timeout: const Duration(seconds: 30),
      );

      // ✅ Backend'den gelen { "results": [...] } yapısını modele gönderiyoruz.
      // Modelimiz artık içindeki productName ve parçalanmış GTIN verilerini karşılayacak.
      return QrLookupResponse.fromJson(decodedData);
    } catch (e) {
      print('❌ QrService Hatası: $e');
      rethrow;
    }
  }
}
