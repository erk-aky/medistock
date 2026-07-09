import 'package:flutter/material.dart';
import 'payment_page.dart';

class SubscriptionPage extends StatelessWidget {
  const SubscriptionPage({super.key});

  // Medikal Renk Paleti
  static const Color primaryColor = Color(0xFFB71C1C);
  static const Color accentColor = Color(0xFFEF5350);
  static const Color healthTeal = Color(0xFF00ADB5);  // Medikal turkuaz
  static const Color bgColor = Color(0xFFF9FBFF);     // Saf arka plan

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text("Planınızı Belirleyin", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: primaryColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Üst Bilgi Bölümü
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.security_update_good_rounded, size: 50, color: healthTeal),
                  const SizedBox(height: 15),
                  const Text(
                    "Sınırsız Eczane Yönetimi",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: primaryColor),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Deneme süreniz sona erdi. İş akışınızı aksatmamak için profesyonel bir pakete geçin.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.blueGrey.shade600, height: 1.4),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildPlanCard(
                    context,
                    title: "Aylık Profesyonel",
                    price: "199",
                    period: "/ Ay",
                    description: "Küçük ölçekli eczaneler için esnek çözüm.",
                    icon: Icons.access_time_filled_rounded,
                    color: accentColor,
                    features: ["Sınırsız QR Tarama", "Excel Rapor Desteği", "Canlı Destek"],
                  ),
                  const SizedBox(height: 20),
                  _buildPlanCard(
                    context,
                    title: "Yıllık Kurumsal",
                    price: "1.890",
                    period: "/ Yıl",
                    description: "En popüler ve en karlı eczane tercihi.",
                    icon: Icons.verified_user_rounded,
                    color: healthTeal,
                    isPopular: true,
                    features: ["Sınırsız QR Tarama", "Excel Rapor Desteği", "Öncelikli Destek", "3 Cihazda Kullanım"],
                  ),
                ],
              ),
            ),
            
            // Güven Rozeti
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: Colors.grey),
                  SizedBox(width: 5),
                  Text("256-bit SSL Güvenli Ödeme", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context, {
    required String title,
    required String price,
    required String period,
    required String description,
    required IconData icon,
    required Color color,
    required List<String> features,
    bool isPopular = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: isPopular ? Border.all(color: color, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          if (isPopular)
            Positioned(
              top: 0,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
                ),
                child: const Text(
                  "EN AVANTAJLI",
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: color, size: 28),
                    ),
                    const SizedBox(width: 15),
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryColor)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text("₺$price", style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: color)),
                    Text(period, style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(description, style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13)),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(height: 1),
                ),
                // Özellik Listesi
                ...features.map((feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded, size: 18, color: color.withOpacity(0.7)),
                      const SizedBox(width: 10),
                      Text(feature, style: const TextStyle(fontSize: 14, color: Colors.black87)),
                    ],
                  ),
                )).toList(),
                const SizedBox(height: 25),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PaymentPage(planName: title, price: "₺$price")),
                  ),
                  child: const Text("Seç ve Ödemeye Geç", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}