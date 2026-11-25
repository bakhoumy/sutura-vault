import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/database/database_helper.dart';
import 'package:sutura_vault/core/security/security_service.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';
import 'package:sutura_vault/features/auth/pin_input_pad.dart';

/// Écran d'initialisation souveraine au premier lancement (SEC-03).
class OnboardingPinSetupScreen extends StatefulWidget {
  const OnboardingPinSetupScreen({
    required this.onVaultInitialized,
    super.key,
  });

  final VoidCallback onVaultInitialized;

  @override
  State<OnboardingPinSetupScreen> createState() =>
      _OnboardingPinSetupScreenState();
}

class _OnboardingPinSetupScreenState extends State<OnboardingPinSetupScreen> {
  int _step = 0; // 0 = Forge PIN, 1 = Confirmation
  int _attemptCounter = 0;
  String? _firstPin;
  String? _errorText;
  bool _isCreating = false;

  Future<void> _handlePinCompleted(String pin) async {
    if (_isCreating) return;

    if (_step == 0) {
      setState(() {
        _firstPin = pin;
        _step = 1;
        _errorText = null;
      });
      return;
    }

    if (pin != _firstPin) {
      HapticFeedback.heavyImpact();
      setState(() {
        _firstPin = null;
        _step = 0;
        _attemptCounter++;
        _errorText = 'Les deux codes PIN ne correspondent pas. Recommencez.';
      });
      return;
    }

    setState(() {
      _isCreating = true;
      _errorText = null;
    });

    try {
      final derivedKey = await SecurityService.instance.initializeMasterPin(pin);
      await DatabaseHelper.instance.openVault(
        derivedKey: derivedKey,
        isDecoy: false,
      );

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      widget.onVaultInitialized();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _isCreating = false;
        _firstPin = null;
        _step = 0;
        _attemptCounter++;
        _errorText = 'Erreur d\'initialisation du coffre : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConfirm = _step == 1;

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
                      color: OledTheme.accentEmerald.withValues(alpha: 0.45),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 32,
                    color: OledTheme.accentEmerald,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'SUTURA VAULT',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.2,
                    color: OledTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isConfirm
                      ? 'Confirmez votre Master PIN'
                      : 'Forgez votre Master PIN (6 chiffres)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: OledTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isConfirm
                      ? 'Saisissez à nouveau votre code pour sceller votre coffre AES-256.'
                      : 'Zéro Cloud, zéro code par défaut. Ce PIN chiffre directement votre base locale.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: OledTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),

                if (_isCreating)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        CircularProgressIndicator(
                          color: OledTheme.accentEmerald,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Scellement SQLCipher AES-256 en cours...',
                          style: TextStyle(
                            color: OledTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  // Règle #6 : ValueKey unique par étape du PinInputPad
                  PinInputPad(
                    key: ValueKey<String>(
                      'onboarding_step_${_step}_attempt_$_attemptCounter',
                    ),
                    scramble: false,
                    errorText: _errorText,
                    onCompleted: _handlePinCompleted,
                  ),

                const SizedBox(height: 18),
                if (isConfirm && !_isCreating)
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _step = 0;
                        _firstPin = null;
                        _errorText = null;
                      });
                    },
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Modifier le premier code'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}