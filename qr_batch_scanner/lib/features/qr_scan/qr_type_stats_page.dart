import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/models/qr_lookup_result.dart';

class QrTypeStatsPage extends StatelessWidget {
  final List<QrLookupResultWithCount> history;

  const QrTypeStatsPage({
    super.key,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // --- ANALİZ MANTIĞI ---
    int criticalCount = 0; // 0-3 Ay (Çöp olma riski)
    int warningCount = 0;  // 3-6 Ay (İade potansiyeli)
    int safeCount = 0;     // 6+ Ay (Güvenli)
    int unknownCount = 0;  // Miadı bilinmeyen

    for (var item in history) {
      final expiry = item.qr.data?.expiryDate;
      if (expiry == null) {
        unknownCount++;
        continue;
      }

      final diffMonths = (expiry.year - now.year) * 12 + expiry.month - now.month;

      if (diffMonths <= 3) {
        criticalCount++;
      } else if (diffMonths <= 6) {
        warningCount++;
      } else {
        safeCount++;
      }
    }

    final total = history.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Miad Analiz Panosu'),
        backgroundColor: const Color(0xFFB71C1C),
        elevation: 0,
      ),
      body: total == 0
          ? const Center(child: Text('Analiz edilecek veri bulunamadı.'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. ÜST RİSK KARTLARI
                  Row(
                    children: [
                      _buildActionCard(
                        context,
                        "KRİTİK (0-3 Ay)",
                        "$criticalCount Adet",
                        Colors.redAccent,
                        Icons.dangerous_outlined,
                        "Acil satış veya imha!",
                      ),
                      const SizedBox(width: 12),
                      _buildActionCard(
                        context,
                        "İADE (3-6 Ay)",
                        "$warningCount Adet",
                        Colors.orangeAccent,
                        Icons.assignment_return_outlined,
                        "Depo iade sürecini başlat.",
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 2. GRAFİK VE DAĞILIM
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Text(
                            "Stok Risk Dağılımı",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 200,
                            child: PieChart(
                              PieChartData(
                                sectionsSpace: 5,
                                centerSpaceRadius: 50,
                                sections: [
                                  PieChartSectionData(value: criticalCount.toDouble(), color: Colors.redAccent, radius: 50, showTitle: false),
                                  PieChartSectionData(value: warningCount.toDouble(), color: Colors.orangeAccent, radius: 45, showTitle: false),
                                  PieChartSectionData(value: safeCount.toDouble(), color: Colors.greenAccent, radius: 40, showTitle: false),
                                  PieChartSectionData(value: unknownCount.toDouble(), color: Colors.grey, radius: 35, showTitle: false),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _buildLegendRow("0-3 Ay (Kritik)", criticalCount, Colors.redAccent),
                          _buildLegendRow("3-6 Ay (İade Adayı)", warningCount, Colors.orangeAccent),
                          _buildLegendRow("6+ Ay (Güvenli)", safeCount, Colors.greenAccent),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 3. STRATEJİK ÖNERİ PANELİ
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: const Color(0xFFFFCDD2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lightbulb_outline, color: const Color(0xFFE53935)),
                            SizedBox(width: 8),
                            Text("Eczacıya Notlar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildAdviceText(criticalCount > 0 
                            ? "🚨 $criticalCount adet ilacın süresi dolmak üzere. Bunları rafın en önüne çekin veya imha listesine alın."
                            : "✅ Yakın vadede imha edilecek ilaç görünmüyor."),
                        const SizedBox(height: 8),
                        _buildAdviceText(warningCount > 0 
                            ? "📦 $warningCount adet ilaç iade dönemine giriyor. Selçuk Ecza iade listesini hazırlamanızı öneririm."
                            : "👍 İade edilecek ilaç stoğunuz şu an kontrol altında."),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildActionCard(BuildContext context, String title, String value, Color color, IconData icon, String subtitle) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 12),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.withOpacity(0.8))),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text("$count Kutu", style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAdviceText(String text) {
    return Text(text, style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4));
  }
}