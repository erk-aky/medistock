import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../models/qr_lookup_result.dart';

class QrService {
  final String baseUrl;

  // Constructor: baseUrl verilmezse ApiConstants'tan çeker
  QrService({String? baseUrl}) : baseUrl = baseUrl ?? ApiConstants.baseUrl;

  /// FOTOĞRAF GÖNDER → BACKEND → SADECE JSON (KOORDİNAT + DB VERİLERİ)
  Future<QrLookupResponse> uploadQrImage(File imageFile) async {
    if (!imageFile.existsSync()) {
      throw Exception('Resim dosyası bulunamadı');
    }

    // Backend'deki [Route("api/qr/lookup")] yapısına uygun adres
    final uri = Uri.parse(ApiConstants.qrLookup);

    final request = http.MultipartRequest('POST', uri);
    request.headers['ngrok-skip-browser-warning'] = 'true';
    
    // ✅ Backend: form.Files["image"] bekliyor.
    request.files.add(
      await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
      ),
    );

    print('---------- 🚀 QR API ISTEGI (AKILLI PARÇALAMA MODU) ----------');
    print('Hedef Adres: $uri');
    print('Dosya Yolu: ${imageFile.path}');
    print('--------------------------------------');

    try {
      // Backend artık parçalama ve DB sorgusu yaptığı için timeout'u 30 saniyeye çektim (ideal süre)
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      print('---------- 📥 API CEVABI ----------');
      print('Durum Kodu: ${response.statusCode}');
      
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Sunucu hatası: ${response.statusCode}');
      }

      final Map<String, dynamic> decodedData = jsonDecode(response.body);

      // ✅ Backend'den gelen { "results": [...] } yapısını modele gönderiyoruz.
      // Modelimiz artık içindeki productName ve parçalanmış GTIN verilerini karşılayacak.
      return QrLookupResponse.fromJson(decodedData);

    } on SocketException {
      throw Exception('Sunucuya ulaşılamadı. Bağlantınızı kontrol edin.');
    } catch (e) {
      print('❌ QrService Hatası: $e');
      rethrow;
    }
  }
}