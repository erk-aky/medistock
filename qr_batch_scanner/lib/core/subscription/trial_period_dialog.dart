import 'package:flutter/material.dart';

// Deneme süresinin kalan zamanını ya da bittiğini gösteren abonelik penceresini açar
void showTrialPeriodDialog(BuildContext context, String remainingTime) {
  final bool isExpired = remainingTime == "Deneme Süresi Doldu";
  const Color primaryColor = Color(0xFFB71C1C);
  const Color healthTeal = Color(0xFF00ADB5);
  const Color expiredRed = Color(0xFFD9534F);

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      return PopScope(
        canPop: true,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: Colors.white,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 25),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isExpired
                          ? [expiredRed, expiredRed.withOpacity(0.8)]
                          : [primaryColor, healthTeal],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          isExpired ? Icons.lock_reset_rounded : Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 50,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isExpired ? "Süreniz Doldu" : "Ücretsiz Deneme",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    child: Column(
                      children: [
                        Text(
                          isExpired
                              ? "Deneme süreniz sona erdi. Profesyonel araçları kullanmaya devam etmek için aboneliğinizi başlatın."
                              : "Şu an ücretsiz deneme sürümünü kullanıyorsunuz. Tüm özelliklere tam erişiminiz var.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 15, height: 1.4),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isExpired ? expiredRed.withOpacity(0.1) : healthTeal.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: isExpired ? expiredRed.withOpacity(0.3) : healthTeal.withOpacity(0.3)
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.timer_outlined, size: 18, color: isExpired ? expiredRed : healthTeal),
                              const SizedBox(width: 8),
                              const Text("Kalan Durum: ", style: TextStyle(fontWeight: FontWeight.w600)),
                              Text(remainingTime, style: TextStyle(color: isExpired ? expiredRed : healthTeal, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isExpired ? primaryColor : healthTeal,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            // Navigator.push(...)
                          },
                          child: const Text("Planları İncele / Abone Ol"),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 28),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
