import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../network/api_client.dart';
import 'its_credential_store.dart';

class ItsStatusService {
  static final ItsStatusService instance = ItsStatusService();

  final ApiClient _apiClient = ApiClient();

  // Kullanıcının dış IP adresini döner, bulamazsa tespit edilemedi yazar
  Future<String> getPublicIP() async {
    try {
      final response = await http.get(Uri.parse(ExternalUrls.publicIp)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (e) {
      debugPrint("IP tespiti başarısız: $e");
    }
    return "Tespit edilemedi";
  }

  // İlacın durumunu İTS'den sorgular ve dönen kodun açıklamasını backend'den alıp döner
  Future<String?> checkDrugStatus({
    required String userId,
    required String gtin,
    required String sn,
    required String lot,
    required String skt,
  }) async {
    final credentials = await ItsCredentialStore.instance.read(userId);
    final String gln = credentials.gln.trim();
    final String pass = credentials.password.trim();

    try {
      debugPrint("🔑 [ADIM 1] İTS Token İsteniyor...");

      final tokenResponse = await http.post(
        Uri.parse(ExternalUrls.itsToken),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "username": gln,
          "password": pass,
        }),
      ).timeout(const Duration(seconds: 10));

      if (tokenResponse.statusCode == 200) {
        final tokenData = jsonDecode(tokenResponse.body);
        String accessToken = tokenData['access_token'] ?? tokenData['accessToken'] ?? tokenData['token'] ?? "";

        if (accessToken.isEmpty) return "Hata: İTS yetki anahtarı alınamadı.";

        debugPrint("🌐 [ADIM 2] İlaç İTS'ye Sorgulanıyor...");

        final Map<String, dynamic> requestBody = {
          "productList": [
            {
              "gtin": gtin.padLeft(14, '0'),
              "sn": sn,
              "bn": lot,
              "xd": skt.length >= 10 ? skt.substring(0, 10) : skt
            }
          ]
        };

        final response = await http.post(
          Uri.parse(ExternalUrls.itsCheckStatus),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final resData = jsonDecode(response.body);
          var uc = resData['responseObjectList']?[0]?['uc'] ?? "Bilinmiyor";

          debugPrint("📦 [ITS] Dönen UC Kodu: $uc");

          try {
            debugPrint("🌐 [ADIM 3] Backend'den resmi açıklama isteniyor...");
            final backendData = await _apiClient.post(ApiConstants.itsResolveCode, {"code": uc.toString()});
            return backendData['message'] ?? uc.toString();
          } on ApiException catch (e) {
            debugPrint("⚠️ Backend Hatası: $e");
            if (e.statusCode != null) return "Kod: $uc (Açıklama getirilemedi)";
            return "Kod: $uc (Sunucu bağlantı hatası)";
          } catch (e) {
            debugPrint("⚠️ Backend Hatası: $e");
            return "Kod: $uc (Sunucu bağlantı hatası)";
          }
        } else {
          return "İTS servisi hata döndürdü: ${response.statusCode}";
        }
      } else if (tokenResponse.statusCode == 401 || tokenResponse.statusCode == 403) {
        return "İTS Kullanıcı adı veya şifre hatalı.";
      } else {
        return "İTS Bağlantı hatası: ${tokenResponse.statusCode}";
      }
    } on SocketException {
      return "İnternet bağlantısı yok veya sunucuya ulaşılamıyor.";
    } catch (e) {
      return "Beklenmedik hata: $e";
    }
  }
}
