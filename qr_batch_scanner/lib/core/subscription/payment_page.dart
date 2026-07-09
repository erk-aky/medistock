import 'package:flutter/material.dart';

class PaymentPage extends StatefulWidget {
  final String planName;
  final String price;

  const PaymentPage({super.key, required this.planName, required this.price});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  // Medikal Tema Renkleri (SubscriptionPage ile uyumlu)
  static const Color primaryColor = Color(0xFFB71C1C);
  static const Color healthTeal = Color(0xFF00ADB5);
  static const Color bgColor = Color(0xFFF9FBFF);

  bool _isProcessing = false;

  void _handlePayment() async {
    setState(() => _isProcessing = true);

    // Backend isteği simülasyonu (2 saniye bekleme)
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _isProcessing = false);
      
      // Başarı Mesajı
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Ödeme Başarılı! Aboneliğiniz aktif edildi."),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Başarılı ödeme sonrası her şeyi kapat ve ana ekrana dön
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text("Ödeme Bilgileri", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: primaryColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isProcessing 
        ? const Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: healthTeal),
              SizedBox(height: 20),
              Text("İşleminiz Güvenle Gerçekleştiriliyor...", style: TextStyle(color: primaryColor, fontWeight: FontWeight.w600)),
            ],
          ))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Özet Kartı
                _buildSummaryHeader(),
                const SizedBox(height: 25),

                // 2. Sanal Kart Görünümü (Psikolojik Güven)
                _buildVirtualCardPreview(),
                const SizedBox(height: 30),

                // 3. Form Alanları
                const Text("Kart Bilgileri", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor)),
                const SizedBox(height: 15),
                _buildTextField("Kart Sahibi", Icons.person_outline),
                const SizedBox(height: 15),
                _buildTextField("Kart Numarası", Icons.credit_card, keyboardType: TextInputType.number),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(child: _buildTextField("SKT (AA/YY)", Icons.calendar_today, keyboardType: TextInputType.datetime)),
                    const SizedBox(width: 15),
                    Expanded(child: _buildTextField("CVV", Icons.lock_outline, keyboardType: TextInputType.number)),
                  ],
                ),

                const SizedBox(height: 30),
                
                // 4. Güvenlik Notu
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.verified_user, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text("3D Secure ile Güvenli Ödeme", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),

                const SizedBox(height: 20),

                // 5. Ödeme Butonu
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 5,
                    shadowColor: primaryColor.withOpacity(0.4),
                  ),
                  onPressed: _handlePayment,
                  child: Text("${widget.price} ÖDEMEYİ TAMAMLA", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildSummaryHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: healthTeal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Seçilen Plan", style: TextStyle(color: primaryColor, fontSize: 12)),
              Text(widget.planName, style: const TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          Text(widget.price, style: const TextStyle(color: healthTeal, fontWeight: FontWeight.w900, fontSize: 22)),
        ],
      ),
    );
  }

  Widget _buildVirtualCardPreview() {
    return Container(
      width: double.infinity,
      height: 180,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryColor, Color(0xFF1B6CA8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.contactless, color: Colors.white70, size: 30),
              Text("VISA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20, fontStyle: FontStyle.italic)),
            ],
          ),
          const Text("**** **** **** ****", style: TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 2)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("KART SAHIBI", style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text(widget.planName.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTextField(String label, IconData icon, {TextInputType? keyboardType}) {
    return TextFormField(
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 14),
        prefixIcon: Icon(icon, color: primaryColor, size: 20),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: healthTeal, width: 2),
        ),
      ),
    );
  }
}