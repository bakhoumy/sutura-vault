import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/database/database_helper.dart';
import 'package:sutura_vault/core/security/security_guard.dart';
import 'package:sutura_vault/core/security/security_service.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';
import 'package:sutura_vault/core/utils/clipboard_vault.dart';
import 'package:sutura_vault/features/auth/lock_screen.dart';
import 'package:sutura_vault/features/auth/onboarding_pin_setup_screen.dart';
import 'package:sutura_vault/features/vault/vault_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
      home: const _SuturaRootGate(),
    );
  }
}

enum _GateStage {
  loading,
  onboarding,
  locked,
  unlocked,
}

class _SuturaRootGate extends StatefulWidget {
  const _SuturaRootGate();

  @override
  State<_SuturaRootGate> createState() => _SuturaRootGateState();
}

class _SuturaRootGateState extends State<_SuturaRootGate>
    with WidgetsBindingObserver {
  _GateStage _stage = _GateStage.loading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final initialized = await SecurityService.instance.isVaultInitialized();
    if (!mounted) return;
    setState(() {
      _stage = initialized ? _GateStage.locked : _GateStage.onboarding;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_stage != _GateStage.unlocked) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      SecurityGuard.instance.markBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_checkAutoLockOnResume());
    }
  }

  Future<void> _checkAutoLockOnResume() async {
    final timeout = await SecurityService.instance.getAutoLockTimeoutSeconds();
    if (!mounted || _stage != _GateStage.unlocked) return;

    if (SecurityGuard.instance.shouldLockOnResume(
      autoLockTimeoutSeconds: timeout,
    )) {
      await _lockVault();
    }
  }

  Future<void> _lockVault() async {
    await DatabaseHelper.instance.lock();
    await ClipboardVault.instance.purgeNow();
    if (!mounted) return;
    setState(() => _stage = _GateStage.locked);
  }

  void _handleVaultWiped() {
    if (!mounted) return;
    setState(() => _stage = _GateStage.onboarding);
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _GateStage.loading:
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(
              color: OledTheme.accentEmerald,
            ),
          ),
        );

      case _GateStage.onboarding:
        return OnboardingPinSetupScreen(
          onVaultInitialized: () {
            if (!mounted) return;
            setState(() => _stage = _GateStage.unlocked);
          },
        );

      case _GateStage.locked:
        return LockScreen(
          onUnlocked: ({required bool isDecoy}) {
            if (!mounted) return;
            setState(() => _stage = _GateStage.unlocked);
          },
        );

      case _GateStage.unlocked:
        return VaultHomeScreen(
          onLockRequested: () => unawaited(_lockVault()),
          onVaultWiped: _handleVaultWiped,
        );
    }
  }
}