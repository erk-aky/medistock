import 'package:flutter/material.dart';
import '../qr_scan_view_model.dart';

// Excel olarak paylaşılacak listeyi seçtiren alt paneli açar
void showExportOptionsSheet(BuildContext context, QrScanViewModel vm) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text("Excel Olarak Paylaş",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            ListTile(
              leading: const Icon(Icons.list_alt, color: Color(0xFFE53935)),
              title: const Text("Tüm Liste"),
              subtitle: const Text("Taranan tüm ilaçları içeren Excel dosyası"),
              onTap: () {
                Navigator.pop(sheetContext);
                _exportFound(context, vm, 'all');
              },
            ),
            ListTile(
              leading: const Icon(Icons.assignment_return, color: Colors.orange),
              title: const Text("İade Listesi"),
              subtitle: const Text("Miadı yaklaşan (90 gün) ilaçları içeren Excel dosyası"),
              onTap: () {
                Navigator.pop(sheetContext);
                _exportFound(context, vm, 'return');
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_toggle_off_rounded, color: Colors.red),
              title: const Text("Miadı Geçenler"),
              subtitle: const Text("Sadece miadı geçmiş ürünleri içeren Excel dosyası"),
              onTap: () {
                Navigator.pop(sheetContext);
                _exportFound(context, vm, 'expired');
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      );
    },
  );
}

// Seçilen türdeki kayıtları Excel olarak paylaşır, kayıt yoksa ya da hata olursa mesaj gösterir
Future<void> _exportFound(BuildContext context, QrScanViewModel vm, String type) async {
  try {
    final exported = await vm.exportFoundToExcel(type: type);
    if (!exported && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(type == 'expired' ? "Miadı geçmiş ürün bulunamadı." : "Dışa aktarılacak kayıt bulunamadı."))
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
    }
  }
}
