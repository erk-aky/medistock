import 'package:flutter/material.dart';
import '../qr_scan_view_model.dart';
import '../../../core/services/its_status_service.dart';

// İTS sorgusundan dönen mesajı, GTIN ve seri numarasıyla birlikte pencerede gösterir
void showItsDialog(BuildContext context, QrScanViewModel vm, String itsMessage, String uc, String gtin, String sn) {
  // Başarı durumunu kontrol et (00000 başarılı, diğerleri genellikle hata/uyarıdır)
  bool isSuccess = uc == '00000' || uc == '40001';
  final Color statusBg = isSuccess ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- ÜST DURUM ÇUBUĞU ---
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      isSuccess ? Icons.verified_user_rounded : Icons.gpp_bad_rounded,
                      size: 50,
                      color: const Color(0xFFB71C1C),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "İTS SORGULAMA",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Color(0xFFB71C1C),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // --- MESAJ KISMI (Backend'den gelen hazır mesaj) ---
                  Text(
                    itsMessage.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB71C1C),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- VERİ KUTUCUKLARI ---
                  _buildInfoRow(Icons.qr_code_2_rounded, "GTIN", gtin),
                  const SizedBox(height: 8),
                  _buildInfoRow(Icons.pin_rounded, "S/N", sn),

                  // --- IP ADRESİ (Sadece yetki hatasında gösterilir) ---
                  if (itsMessage.contains("yetkilendirme") || uc == 'HATA_ERISIM') ...[
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueGrey.withOpacity(0.1)),
                      ),
                      child: FutureBuilder<String>(
                        future: ItsStatusService.instance.getPublicIP(),
                        builder: (context, snapshot) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.language_rounded, size: 16, color: Colors.blueGrey),
                              const SizedBox(width: 8),
                              Text(
                                "BAĞLANTI IP: ${snapshot.data ?? 'Sorgulanıyor...'}",
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 25),

                  // --- BUTON ---
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB71C1C),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "ANLADIM",
                        style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

// İTS penceresindeki GTIN ve S/N satırlarını ikonlu kutu olarak çizer
Widget _buildInfoRow(IconData icon, String label, String value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFB),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.black.withOpacity(0.05)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFB71C1C)),
        const SizedBox(width: 10),
        Text(
          "$label:",
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
      ],
    ),
  );
}
