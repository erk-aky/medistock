import 'package:flutter/material.dart';

import '../../../core/models/qr_lookup_result.dart';

class ScanResultCard extends StatelessWidget {
  final QrLookupResultWithCount item;
  final VoidCallback onDelete;

  const ScanResultCard({super.key, required this.item, required this.onDelete});

  // Taranan ilacın adını ve adedini silme butonuyla birlikte kart olarak gösterir
  @override
  Widget build(BuildContext context) {
    final bool found = item.qr.found;
    // final bool isExpired = item.qr.data?.isExpired ?? false;
    // final bool expirySoon = item.qr.data?.isExpirySoon ?? false;
    final String? productName = item.qr.data?.productName;
    final String displayName = found && productName != null
        ? productName.toUpperCase()
        : item.qr.value;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // -- Sol renkli kenarlık (geçici olarak kapatıldı) --
              // Container(width: 6, color: found ? Colors.teal : Colors.redAccent),
              // const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // -- Durum ve miad badge'leri (geçici olarak kapatıldı) --
                      // Row(
                      //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      //   children: [
                      //     _buildStatusBadge(found),
                      //     if (isExpired)
                      //       _buildExpiredBadge()
                      //     else if (expirySoon)
                      //       _buildExpiryBadge(),
                      //   ],
                      // ),
                      // const SizedBox(height: 12),
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      // -- GTIN / Seri No / SKT satırları (geçici olarak kapatıldı) --
                      // if (found) ...[
                      //   const SizedBox(height: 8),
                      //   _buildMedicineInfo(Icons.qr_code_rounded, 'GTIN', item.qr.data!.gtin ?? '-'),
                      //   _buildMedicineInfo(Icons.numbers_rounded, 'Seri No', item.qr.data!.serialNo ?? '-'),
                      //   _buildMedicineInfo(Icons.calendar_today_rounded, 'SKT',
                      //     item.qr.data!.expiryDate != null
                      //       ? "${item.qr.data!.expiryDate!.day}/${item.qr.data!.expiryDate!.month}/${item.qr.data!.expiryDate!.year}"
                      //       : '-'),
                      // ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${item.count}\nadet',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFFD32F2F),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_rounded, color: Colors.grey),
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Kayıtlı ilaç ya da kayıtsız barkod rozeti, kartta rozetler kapalı olduğu için şimdilik kullanılmıyor
  // ignore: unused_element
  Widget _buildStatusBadge(bool found) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: found ? Colors.teal.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        found ? 'Kayıtlı İlaç' : 'Kayıtsız Barkod',
        style: TextStyle(color: found ? Colors.teal.shade700 : Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  // Miadı yakın rozeti, kartta rozetler kapalı olduğu için şimdilik kullanılmıyor
  // ignore: unused_element
  Widget _buildExpiryBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
      child: Text('MİADI YAKIN', style: TextStyle(color: Colors.orange.shade900, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  // Miadı geçmiş rozeti, kartta rozetler kapalı olduğu için şimdilik kullanılmıyor
  // ignore: unused_element
  Widget _buildExpiredBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8)),
      child: Text('MİADI GEÇMİŞ', style: TextStyle(color: Colors.red.shade900, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  // GTIN, seri no ve SKT satırı, kartta bu satırlar kapalı olduğu için şimdilik kullanılmıyor
  // ignore: unused_element
  Widget _buildMedicineInfo(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFFEF9A9A)),
          const SizedBox(width: 6),
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black54)),
          const SizedBox(width: 6),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: Colors.black87))),
        ],
      ),
    );
  }
}

class ScanEmptyState extends StatelessWidget {
  const ScanEmptyState({super.key});

  // Listede hiç tarama yokken ortada boş kutu ikonu ve mesaj gösterir
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: const Color(0xFFE53935).withOpacity(0.1)),
          const SizedBox(height: 16),
          const Text('Henüz tarama yapılmadı', style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }
}
