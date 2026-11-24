import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Barre de statut & navigation fondues dans le noir OLED (#0D0F12)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: OledTheme.bgPrimary,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const SuturaVaultApp());
}

class SuturaVaultApp extends StatelessWidget {
  const SuturaVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sutura Vault',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: OledTheme.darkTheme,
      home: const _VaultBootstrapScreen(),
    );
  }
}

/// Écran transitoire du Jalon 1 — sera remplacé par le Gatekeeper
/// (Onboarding Master PIN / LockScreen) au Jalon 3.
class _VaultBootstrapScreen extends StatelessWidget {
  const _VaultBootstrapScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: OledTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: OledTheme.accentEmerald.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 38,
                    color: OledTheme.accentEmerald,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'SUTURA VAULT',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.2,
                    color: OledTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Zero-Cloud • Zero-Internet • AES-256 SQLCipher',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: OledTheme.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}