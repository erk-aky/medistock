import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../qr_scan/qr_scan_view_model.dart';
import '../auth/login_page.dart';
import 'account_details_page.dart';
import '../auth/auth_view_model.dart';
import '../../core/services/db_sync_service.dart';

class SettingsPage extends StatelessWidget {
  final QrScanViewModel vm;
  const SettingsPage({super.key, required this.vm});

  static const Color primaryColor = Color(0xFFB71C1C);
  static const Color primaryDark = Color(0xFF1B262C);
  static const Color healthTeal = Color(0xFF00ADB5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FBFF),
      appBar: AppBar(
        title: const Text("Ayarlar", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: primaryColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 20),
          _buildSectionTitle("YÖNETİM"),

          // 🔥 HESAP YÖNETİMİ (Hatasız ve Loglu Versiyon)
          _buildSettingsCard(
            icon: Icons.admin_panel_settings_rounded,
            iconColor: primaryColor,
            title: "Hesap Yönetimi",
            subtitle: "Eczane, lisans ve şube bilgileri",
            onTap: () async {
              final authVm = Provider.of<AuthViewModel>(context, listen: false);
              final prefs = await SharedPreferences.getInstance();

              // 1️⃣ Kimlik tespiti
              final userIdStr = authVm.userId?.toString() ?? "guest";
              final localUsernameKey = 'local_username_$userIdStr';

              // 2️⃣ SharedPreferences'ı tazele
              await prefs.reload();
              final savedUsername = prefs.getString(localUsernameKey);

              // 3️⃣ Karar Mekanizması: Önce VM, yoksa prefs
              // 🔹 GİDECEK USERNAME’i her zaman SP’deki ile eşitle
              String? usernameToFetch = savedUsername ?? authVm.username;

              // 🔹 Eğer SP’de veri varsa, VM’i de senkronize et
              if (savedUsername != null && savedUsername.isNotEmpty) {
                authVm.setUsername(savedUsername); // AuthViewModel’de setter olmalı
              }

              // 🔍 [GELEN - GİDEN LOGU]
              print("---------- [SETTINGS PROFİL KONTROL] ----------");
              print("📥 GELEN (Hafızadaki Eski): ${authVm.username}");
              print("💾 KAYITLI (Sp'den Okunan): $savedUsername");
              print("📤 GİDECEK (İstek Atılan): $usernameToFetch");
              print("-----------------------------------------------");

              // 4️⃣ 🔥 EKLEME: Backend’den en güncel profili çek ve VM’i güncelle
              if (usernameToFetch != null && usernameToFetch.isNotEmpty) {
                try {
                  await authVm.fetchAndUpdateProfile(usernameToFetch);
                } catch (e) {
                  print("❌ Profil Çekme Başarısız: $e");
                  // Hata alsa bile sayfayı aç
                }
              }

              // 5️⃣ Sonra sayfayı aç
              if (context.mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AccountDetailsPage(vm: vm),
                  ),
                );
              }
            },
          ),

          const SizedBox(height: 20),
          _buildSectionTitle("UYGULAMA TERCİHLERİ"),

          _buildSettingsCard(
            icon: Icons.event_note_rounded,
            iconColor: Colors.orange,
            title: "S.K.T Uyarı Limiti",
            subtitle: "Kritik raf ömrü uyarı eşiği",
            trailing: Consumer<QrScanViewModel>(
              builder: (context, vm, child) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<int>(
                    value: vm.expiryMonthLimit,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, color: primaryColor),
                    items: [3, 6, 12, 24].map((int val) {
                      return DropdownMenuItem<int>(
                        value: val,
                        child: Text("$val Ay",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: primaryColor)),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      if (newValue != null) vm.setExpiryMonthLimit(newValue);
                    },
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),
          _buildSectionTitle("GÜVENLİK"),

          _buildSettingsCard(
            icon: Icons.logout_rounded,
            iconColor: Colors.redAccent,
            title: "Oturumu Kapat",
            subtitle: "Sistemi güvenli bir şekilde kapatın",
            onTap: () => _handleLogoutFromSettings(context),
            isDestructive: true,
          ),

          const SizedBox(height: 40),
          const Center(
            child: Text("Sürüm 1.0.2",
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          const SizedBox(height: 4),
          Center(
            child: FutureBuilder<int>(
              future: DbSyncService().getLocalVersion(),
              builder: (context, snapshot) {
                final version = snapshot.data;
                return Text(
                  version == null
                      ? "İlaç veritabanı sürümü: -"
                      : "İlaç veritabanı sürümü: v$version",
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- YARDIMCI WIDGETLAR ---

  Widget _buildSettingsCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDestructive ? Colors.redAccent : primaryColor)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(title,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
              letterSpacing: 1.2)),
    );
  }

  Future<void> _handleLogoutFromSettings(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true, // Dışarıya tıklayınca kapansın
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 16,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Üstteki İkon Alanı
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Colors.redAccent,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              
              // Başlık
              const Text(
                "Oturumu Kapat",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              
              // Açıklama Metni
              Text(
                "Hesabınızdan çıkış yapmak istediğinize emin misiniz? Tekrar girmek için bilgilerinizi kullanmanız gerekecektir.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              
              // Butonlar
              Row(
                children: [
                  // Vazgeç Butonu (Sade)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey[300]!),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "Vazgeç",
                        style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Çıkış Yap Butonu (Kırmızı/Vurgulu)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Çıkış Yap",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    // İşlem Onaylandıysa
    if (confirm == true && context.mounted) {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      
      // ViewModel üzerinden temizliği yap
      await authVm.logout();

      // Login sayfasına yönlendir ve tüm stack'i temizle
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }
}