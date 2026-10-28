import 'package:flutter/material.dart';
import 'package:qr_batch_scanner/features/qr_scan/qr_scan_view_model.dart';

class StockComparisonPage extends StatelessWidget {
  final QrScanViewModel vm;

  const StockComparisonPage({super.key, required this.vm});

  // Tema Renkleri
  static const Color primaryBlue = Color(0xFFB71C1C);
  static const Color healthTeal = Color(0xFF00ADB5);
  static const Color bgSecondary = Color(0xFFF1F5F9);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color errorRose = Color(0xFFE11D48);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: vm.getComparisonResults(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: Text("Veri bulunamadı.")),
          );
        }

        final results = snapshot.data!;
        final stats = results['stats'];

        return Scaffold(
          backgroundColor: bgSecondary,
          appBar: AppBar(
            title: const Text(
              "Sayım Analiz Raporu",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            backgroundColor: primaryBlue,
            foregroundColor: Colors.white,
            centerTitle: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: Column(
            children: [
              _buildHeaderStats(stats),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  children: [
                    _buildCategorySection(
                        "Eksik Ürünler",
                        results['missing'],
                        warningAmber,
                        Icons.inventory_2_outlined),
                    const SizedBox(height: 20),
                    _buildCategorySection(
                        "Fazla / Tanımsız",
                        results['extra'],
                        errorRose,
                        Icons.assignment_late_outlined),
                    const SizedBox(height: 20),
                    _buildCategorySection(
                        "Tamamlanan",
                        results['matched'],
                        healthTeal,
                        Icons.check_circle_rounded),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: _buildBottomAction(context),
        );
      },
    );
  }

  Widget _buildHeaderStats(Map<String, dynamic> stats) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: primaryBlue,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStatItem("BEKLENEN", "${stats['expected']}", Icons.list_alt),
          _buildStatItem("OKUNAN", "${stats['scanned']}",
              Icons.qr_code_scanner,
              isAccent: true),
          _buildStatItem(
              "DOĞRULUK", "%${stats['accuracy']}", Icons.analytics_outlined),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon,
      {bool isAccent = false}) {
    return Column(
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
              color: isAccent ? healthTeal : Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold),
        ),
        Text(label,
            style: const TextStyle(
                color: Colors.white60, fontSize: 10, letterSpacing: 1)),
      ],
    );
  }

  Widget _buildCategorySection(
      String title, List items, Color color, IconData icon) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primaryBlue.withOpacity(0.8))),
              const Spacer(),
              Text("${items.length} Kalem",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
        ...items.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(
                  item['name'] ?? "Bilinmeyen Ürün",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: Text(
                  "Barkod: ${item['barcode']}",
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    "${item['scanned']} / ${item['expected']}",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 13),
                  ),
                ),
              ),
            ))
      ],
    );
  }

  Widget _buildBottomAction(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5))
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop('resume'),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
              label: const Text(
                "TARAMAYA DEVAM ET",
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  await vm.exportComparisonReport();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Excel Hatası: ${e.toString()}")),
                    );
                  }
                }
              },
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              label: const Text(
                "ANALİZ RAPORUNU PAYLAŞ",
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: healthTeal,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () async {
                await vm.clearStockSession();
                if (!context.mounted) return;
                Map<String, int>? loaded;
                try {
                  loaded = await vm.pickExcelFile();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red),
                    );
                  }
                }
                if (!context.mounted) return;
                if (loaded != null && loaded.isNotEmpty) {
                  Navigator.of(context).pop('show_summary');
                }
              },
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text(
                "YENİ SAYIM BAŞLAT",
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: warningAmber,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}