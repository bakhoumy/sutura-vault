import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/security/pin_recovery_service.dart';
import 'package:sutura_vault/core/security/security_service.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';

/// Configuration style Windows des 3 questions de récupération du Master PIN.
class PinRecoverySetupScreen extends StatefulWidget {
  const PinRecoverySetupScreen({super.key});

  @override
  State<PinRecoverySetupScreen> createState() => _PinRecoverySetupScreenState();
}

class _PinRecoverySetupScreenState extends State<PinRecoverySetupScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _pinCtrl = TextEditingController();
  final List<TextEditingController> _answerCtrls =
      List<TextEditingController>.generate(3, (_) => TextEditingController());

  final List<String> _selectedQuestions = <String>[
    PinRecoveryService.predefinedQuestions[0],
    PinRecoveryService.predefinedQuestions[1],
    PinRecoveryService.predefinedQuestions[2],
  ];

  bool _obscureAnswers = true;
  bool _isSaving = false;
  bool _alreadyConfigured = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadExisting());
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    for (final c in _answerCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final existing = await PinRecoveryService.instance.getConfiguredQuestions();
    if (!mounted) return;
    if (existing != null && existing.length == 3) {
      setState(() {
        _alreadyConfigured = true;
        for (var i = 0; i < 3; i++) {
          if (PinRecoveryService.predefinedQuestions.contains(existing[i])) {
            _selectedQuestions[i] = existing[i];
          }
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;

    if (_selectedQuestions.toSet().length != 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choisissez 3 questions différentes.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final verification =
          await SecurityService.instance.verifyPin(_pinCtrl.text.trim());
      if (!mounted) return;

      if (verification.status != PinAuthStatus.masterSuccess ||
          verification.derivedKey == null) {
        HapticFeedback.heavyImpact();
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Master PIN actuel incorrect.')),
        );
        return;
      }

      final items = List<SecurityQuestionAnswer>.generate(
        3,
        (i) => SecurityQuestionAnswer(
          question: _selectedQuestions[i],
          answer: _answerCtrls[i].text,
        ),
      );

      await PinRecoveryService.instance.configureRecovery(
        masterDerivedKey: verification.derivedKey!,
        items: items,
      );

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Questions de récupération scellées en PBKDF2-HMAC-SHA256.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _clearRecovery() async {
    await PinRecoveryService.instance.clearRecovery();
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Questions de récupération supprimées du Keystore.'),
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Questions de Récupération',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: _obscureAnswers
                ? 'Afficher les réponses'
                : 'Masquer les réponses',
            icon: Icon(
              _obscureAnswers
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () => setState(() => _obscureAnswers = !_obscureAnswers),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: OledTheme.surfaceCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: OledTheme.accentBlue.withValues(alpha: 0.4),
                ),
              ),
              child: const Text(
                'Récupération hors-ligne Zero-Knowledge : vos 3 réponses ne sont jamais stockées en clair. Elles chiffrent localement une enveloppe permettant de réinitialiser votre Master PIN sans perdre vos données.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: OledTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Votre Master PIN actuel (6 chiffres) *',
                counterText: '',
              ),
              validator: (v) =>
                  (v == null || !SecurityService.isValidPinFormat(v.trim()))
                      ? 'Saisissez votre Master PIN à 6 chiffres'
                      : null,
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < 3; i++) ...[
              Text(
                'Question de sécurité ${i + 1} / 3',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: OledTheme.accentEmerald,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedQuestions[i],
                isExpanded: true, // Règle #6
                dropdownColor: OledTheme.surfaceCard,
                items: PinRecoveryService.predefinedQuestions
                    .map(
                      (q) => DropdownMenuItem<String>(
                        value: q,
                        child: Text(q, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedQuestions[i] = v);
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _answerCtrls[i],
                obscureText: _obscureAnswers,
                decoration: InputDecoration(
                  labelText: 'Réponse ${i + 1} (insensible à la casse) *',
                ),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Minimum 2 caractères'
                    : null,
              ),
              const SizedBox(height: 16),
            ],
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: OledTheme.accentEmerald,
                foregroundColor: OledTheme.bgPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isSaving ? null : () => unawaited(_save()),
              child: Text(
                _isSaving
                    ? 'Scellement PBKDF2...'
                    : 'Enregistrer les 3 questions',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (_alreadyConfigured) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: OledTheme.accentRed,
                  side: const BorderSide(color: OledTheme.accentRed),
                ),
                onPressed: _isSaving ? null : () => unawaited(_clearRecovery()),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Désactiver & supprimer la récupération'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}