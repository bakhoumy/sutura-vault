import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/database/database_helper.dart';
import 'package:sutura_vault/core/security/pin_recovery_service.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';
import 'package:sutura_vault/features/auth/pin_input_pad.dart';

/// Parcours « Code PIN oublié ? » style Windows (3 questions -> Nouveau PIN -> PRAGMA rekey).
class PinRecoveryScreen extends StatefulWidget {
  const PinRecoveryScreen({super.key});

  @override
  State<PinRecoveryScreen> createState() => _PinRecoveryScreenState();
}

class _PinRecoveryScreenState extends State<PinRecoveryScreen> {
  final List<TextEditingController> _answerCtrls =
      List<TextEditingController>.generate(3, (_) => TextEditingController());

  List<String> _questions = <String>[];
  bool _isLoading = true;
  bool _isBusy = false;
  bool _obscureAnswers = true;
  String? _errorText;

  // Étapes : 0 = Réponses, 1 = Nouveau PIN, 2 = Confirmer Nouveau PIN
  int _step = 0;
  int _padAttempt = 0;
  String? _recoveredOldKey;
  List<String>? _verifiedAnswers;
  String? _pendingNewPin;

  @override
  void initState() {
    super.initState();
    unawaited(_loadQuestions());
  }

  @override
  void dispose() {
    for (final c in _answerCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    final questions = await PinRecoveryService.instance.getConfiguredQuestions();
    if (!mounted) return;
    setState(() {
      _questions = questions ?? <String>[];
      _isLoading = false;
    });
  }

  Future<void> _verifyAnswers() async {
    if (_isBusy) return;
    final answers = _answerCtrls.map((c) => c.text).toList();
    if (answers.any((a) => a.trim().isEmpty)) {
      setState(() => _errorText = 'Répondez aux 3 questions de sécurité.');
      return;
    }

    setState(() {
      _isBusy = true;
      _errorText = null;
    });

    try {
      final recoveredKey =
          await PinRecoveryService.instance.verifyAnswersAndUnwrapKey(answers);
      if (!mounted) return;

      if (recoveredKey == null) {
        HapticFeedback.heavyImpact();
        setState(() {
          _isBusy = false;
          _errorText = 'Une ou plusieurs réponses sont incorrectes.';
        });
        return;
      }

      HapticFeedback.mediumImpact();
      setState(() {
        _isBusy = false;
        _recoveredOldKey = recoveredKey;
        _verifiedAnswers = answers;
        _step = 1;
        _errorText = null;
      });
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _isBusy = false;
        _errorText = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _handleNewPinCompleted(String pin) async {
    if (_isBusy) return;

    if (_step == 1) {
      setState(() {
        _pendingNewPin = pin;
        _step = 2;
        _errorText = null;
      });
      return;
    }

    if (pin != _pendingNewPin) {
      HapticFeedback.heavyImpact();
      setState(() {
        _pendingNewPin = null;
        _step = 1;
        _padAttempt++;
        _errorText = 'Les deux codes PIN ne correspondent pas.';
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _errorText = null;
    });

    try {
      final newKey =
          await PinRecoveryService.instance.resetMasterPinWithRecoveredKey(
        recoveredOldKey: _recoveredOldKey!,
        verifiedAnswers: _verifiedAnswers!,
        newPin: pin,
      );

      await DatabaseHelper.instance.openVault(
        derivedKey: newKey,
        isDecoy: false,
      );

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _isBusy = false;
        _pendingNewPin = null;
        _step = 1;
        _padAttempt++;
        _errorText = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Récupération du Master PIN',
          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_step == 0)
            IconButton(
              icon: Icon(
                _obscureAnswers
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () =>
                  setState(() => _obscureAnswers = !_obscureAnswers),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: OledTheme.accentEmerald),
            )
          : _questions.length != 3
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aucune question de récupération configurée sur cet appareil.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: OledTheme.textSecondary),
                    ),
                  ),
                )
              : _step == 0
                  ? _buildQuestionsForm()
                  : _buildNewPinStep(),
    );
  }

  Widget _buildQuestionsForm() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
      children: [
        const Text(
          'Répondez à vos 3 questions de sécurité pour déverrouiller la clé SQLCipher et définir un nouveau Master PIN :',
          style: TextStyle(fontSize: 13, color: OledTheme.textSecondary),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < 3; i++) ...[
          Text(
            '${i + 1}. ${_questions[i]}',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: OledTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _answerCtrls[i],
            obscureText: _obscureAnswers,
            decoration: InputDecoration(
              hintText: 'Votre réponse ${i + 1}',
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_errorText != null) ...[
          Text(
            _errorText!,
            style: const TextStyle(
              color: OledTheme.accentRed,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: OledTheme.accentEmerald,
            foregroundColor: OledTheme.bgPrimary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _isBusy ? null : () => unawaited(_verifyAnswers()),
          child: Text(
            _isBusy ? 'Vérification PBKDF2...' : 'Vérifier mes 3 réponses',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildNewPinStep() {
    final isConfirm = _step == 2;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.verified_outlined,
              size: 42,
              color: OledTheme.accentEmerald,
            ),
            const SizedBox(height: 14),
            Text(
              isConfirm
                  ? 'Confirmez votre nouveau Master PIN'
                  : 'Définissez un nouveau Master PIN',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: OledTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Vos données seront automatiquement rechiffrées (PRAGMA rekey).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: OledTheme.textSecondary),
            ),
            const SizedBox(height: 22),
            if (_isBusy)
              const CircularProgressIndicator(color: OledTheme.accentEmerald)
            else
              PinInputPad(
                key: ValueKey<String>(
                  'recovery_pin_step_${_step}_attempt_$_padAttempt',
                ),
                scramble: false,
                errorText: _errorText,
                onCompleted: _handleNewPinCompleted,
              ),
          ],
        ),
      ),
    );
  }
}