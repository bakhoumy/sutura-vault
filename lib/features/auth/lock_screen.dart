import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/database/database_helper.dart';
import 'package:sutura_vault/core/security/pin_recovery_service.dart';
import 'package:sutura_vault/core/security/security_service.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';
import 'package:sutura_vault/features/auth/pin_input_pad.dart';
import 'package:sutura_vault/features/auth/pin_recovery_screen.dart';

/// Sas d'authentification principal de SUTURA VAULT.
class LockScreen extends StatefulWidget {
  const LockScreen({
    required this.onUnlocked,
    super.key,
  });

  final void Function({required bool isDecoy}) onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _scrambleEnabled = true;
  bool _biometricsEnabled = false;
  bool _hasRecovery = false;
  bool _isBusy = false;
  int _lockoutRemainingSeconds = 0;
  int _padResetCounter = 0;
  String? _errorText;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSecurityState());
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSecurityState() async {
    final service = SecurityService.instance;
    final scramble = await service.isScramblePadEnabled();
    final bioAllowed = await service.isBiometricsUserAllowed();
    final bioAvailable =
        bioAllowed ? await service.isDeviceBiometricsAvailable() : false;
    final remaining = await service.getRemainingLockoutSeconds();
    final hasRecovery =
        await PinRecoveryService.instance.isRecoveryConfigured();

    if (!mounted) return;
    setState(() {
      _scrambleEnabled = scramble;
      _biometricsEnabled = bioAllowed && bioAvailable;
      _hasRecovery = hasRecovery;
      _lockoutRemainingSeconds = remaining;
    });

    if (remaining > 0) {
      _startLockoutCountdown(remaining);
    } else if (bioAllowed && bioAvailable) {
      unawaited(_tryBiometrics());
    }
  }

  void _startLockoutCountdown(int seconds) {
    _lockoutTimer?.cancel();
    setState(() {
      _lockoutRemainingSeconds = seconds;
      _errorText = null;
    });

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final remaining =
          await SecurityService.instance.getRemainingLockoutSeconds();
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (remaining <= 0) {
        timer.cancel();
        setState(() {
          _lockoutRemainingSeconds = 0;
          _errorText = null;
          _padResetCounter++;
        });
      } else {
        setState(() => _lockoutRemainingSeconds = remaining);
      }
    });
  }

  Future<void> _tryBiometrics() async {
    if (_isBusy || _lockoutRemainingSeconds > 0 || !_biometricsEnabled) return;

    setState(() => _isBusy = true);
    try {
      final derivedKey =
          await SecurityService.instance.authenticateWithBiometrics();
      if (!mounted) return;

      if (derivedKey != null) {
        await DatabaseHelper.instance.openVault(
          derivedKey: derivedKey,
          isDecoy: false,
        );
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        widget.onUnlocked(isDecoy: false);
        return;
      }
    } catch (_) {
      // Retour silencieux sur le pavé PIN
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _handlePinCompleted(String pin) async {
    if (_isBusy || _lockoutRemainingSeconds > 0) return;

    setState(() {
      _isBusy = true;
      _errorText = null;
    });

    try {
      final result = await SecurityService.instance.verifyPin(pin);
      if (!mounted) return;

      switch (result.status) {
        case PinAuthStatus.masterSuccess:
          await DatabaseHelper.instance.openVault(
            derivedKey: result.derivedKey!,
            isDecoy: false,
          );
          if (!mounted) return;
          HapticFeedback.mediumImpact();
          widget.onUnlocked(isDecoy: false);
          return;

        case PinAuthStatus.decoySuccess:
          // SEC-05 : Déni plausible — strictement indiscernable du vrai coffre
          await DatabaseHelper.instance.openVault(
            derivedKey: result.derivedKey!,
            isDecoy: true,
          );
          if (!mounted) return;
          HapticFeedback.mediumImpact();
          widget.onUnlocked(isDecoy: true);
          return;

        case PinAuthStatus.invalidPin:
          HapticFeedback.heavyImpact();
          setState(() {
            _isBusy = false;
            _padResetCounter++;
            _errorText =
                'Code PIN invalide (échec ${result.failedAttempts}/5)';
          });
          return;

        case PinAuthStatus.lockedOut:
          HapticFeedback.heavyImpact();
          setState(() {
            _isBusy = false;
            _padResetCounter++;
          });
          _startLockoutCountdown(result.remainingLockoutSeconds);
          return;
      }
    } catch (_) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _isBusy = false;
        _padResetCounter++;
        _errorText = 'Impossible d\'ouvrir le coffre chiffré.';
      });
    }
  }

  Future<void> _openPinRecovery() async {
    final recovered = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const PinRecoveryScreen(),
      ),
    );
    if (!mounted) return;

    if (recovered == true) {
      widget.onUnlocked(isDecoy: false);
    } else {
      await _loadSecurityState();
    }
  }

  String _formatCountdown(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes == 0) return '${seconds}s';
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final isLockedOut = _lockoutRemainingSeconds > 0;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: OledTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: (isLockedOut
                              ? OledTheme.accentRed
                              : OledTheme.accentEmerald)
                          .withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    isLockedOut ? Icons.timer_outlined : Icons.lock_outline,
                    size: 30,
                    color: isLockedOut
                        ? OledTheme.accentRed
                        : OledTheme.accentEmerald,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'SUTURA VAULT',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.2,
                    color: OledTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isLockedOut
                      ? 'Verrouillage anti-force brute : ${_formatCountdown(_lockoutRemainingSeconds)}'
                      : 'Saisissez votre code PIN à 6 chiffres',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        isLockedOut ? FontWeight.w600 : FontWeight.w400,
                    color: isLockedOut
                        ? OledTheme.accentAmber
                        : OledTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),

                // Règle #6 : ValueKey unique à chaque réinitialisation
                PinInputPad(
                  key: ValueKey<String>('lock_pad_$_padResetCounter'),
                  scramble: _scrambleEnabled,
                  enabled: !_isBusy && !isLockedOut,
                  showBiometricButton: _biometricsEnabled && !isLockedOut,
                  onBiometricPressed: _tryBiometrics,
                  errorText: _errorText,
                  onCompleted: _handlePinCompleted,
                ),

                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StatusPill(
                      icon: _scrambleEnabled
                          ? Icons.shuffle_rounded
                          : Icons.dialpad_rounded,
                      label: _scrambleEnabled
                          ? 'Scramble Pad'
                          : 'Clavier fixe',
                      color: _scrambleEnabled
                          ? OledTheme.accentEmerald
                          : OledTheme.textMuted,
                    ),
                    const SizedBox(width: 10),
                    _StatusPill(
                      icon: _biometricsEnabled
                          ? Icons.fingerprint
                          : Icons.gpp_good_outlined,
                      label: _biometricsEnabled ? 'TEE Actif' : 'PIN Strict',
                      color: _biometricsEnabled
                          ? OledTheme.accentBlue
                          : OledTheme.accentAmber,
                    ),
                  ],
                ),

                if (_hasRecovery && !isLockedOut) ...[
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: () => unawaited(_openPinRecovery()),
                    icon: const Icon(Icons.help_outline, size: 16),
                    label: const Text('Code PIN oublié ?'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: OledTheme.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}