import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/database/database_helper.dart';
import 'package:sutura_vault/core/security/panic_wipe_service.dart';
import 'package:sutura_vault/core/security/security_service.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';
import 'package:sutura_vault/features/backup/backup_restore_screen.dart';
import 'package:sutura_vault/features/vault/models/vault_models.dart';
import 'package:sutura_vault/features/vault/repositories/vault_repository.dart';

/// Centre de Sécurité, Audit Temps Réel & Résilience (Sections 2 & 4.3).
class SecurityCenterScreen extends StatefulWidget {
  const SecurityCenterScreen({
    required this.onLockRequested,
    required this.onVaultWiped,
    super.key,
  });

  final VoidCallback onLockRequested;
  final VoidCallback onVaultWiped;

  @override
  State<SecurityCenterScreen> createState() => _SecurityCenterScreenState();
}

class _SecurityCenterScreenState extends State<SecurityCenterScreen> {
  bool _isLoading = true;
  int _dbSizeBytes = 0;
  VaultCounts _counts = const VaultCounts(
    items: 0,
    documents: 0,
    notes: 0,
    audioMemos: 0,
  );

  bool _scramblePad = true;
  bool _biometricsAllowed = false;
  bool _biometricsHardware = false;
  bool _hasDecoyPin = false;
  int _autoLockSeconds = 30;
  int _clipboardSeconds = 30;

  bool get _isDecoySession => DatabaseHelper.instance.isDecoySession;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
  }

  Future<void> _loadAll() async {
    final sec = SecurityService.instance;
    final size = await DatabaseHelper.instance.getActiveDatabaseSizeBytes();
    final counts = await VaultRepository.instance.getVaultCounts();
    final scramble = await sec.isScramblePadEnabled();
    final bioAllowed = await sec.isBiometricsUserAllowed();
    final bioHardware = await sec.isDeviceBiometricsAvailable();
    final hasDecoy = await sec.hasDecoyPin();
    final autoLock = await sec.getAutoLockTimeoutSeconds();
    final clipboard = await sec.getClipboardPurgeSeconds();

    if (!mounted) return;
    setState(() {
      _dbSizeBytes = size;
      _counts = counts;
      _scramblePad = scramble;
      _biometricsAllowed = bioAllowed;
      _biometricsHardware = bioHardware;
      _hasDecoyPin = hasDecoy;
      _autoLockSeconds = autoLock;
      _clipboardSeconds = clipboard;
      _isLoading = false;
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} Mo';
  }

  /// SEC-06 : Bascule du Mode Zone Hostile (coupe ou réautorise la biométrie).
  Future<void> _toggleHostileMode(bool enableHostileMode) async {
    if (enableHostileMode) {
      await SecurityService.instance.setBiometricsAllowed(allowed: false);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _biometricsAllowed = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mode Zone Hostile actif : biométrie coupée et clé TEE purgée.',
          ),
        ),
      );
      return;
    }

    if (!_biometricsHardware) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun capteur biométrique TEE disponible sur cet appareil.'),
        ),
      );
      return;
    }

    // Demande le Master PIN pour sceller proprement la clé dans le TEE
    final pin = await _promptSinglePin(
      title: 'Autoriser la biométrie TEE',
      subtitle: 'Saisissez votre Master PIN (6 chiffres) pour réactiver la biométrie.',
    );
    if (pin == null || !mounted) return;

    final res = await SecurityService.instance.verifyPin(pin);
    if (!mounted) return;
    if (res.status != PinAuthStatus.masterSuccess || res.derivedKey == null) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Master PIN incorrect.')),
      );
      return;
    }

    await SecurityService.instance.setBiometricsAllowed(
      allowed: true,
      masterDerivedKey: res.derivedKey,
    );
    if (!mounted) return;
    setState(() => _biometricsAllowed = true);
  }

  Future<String?> _promptSinglePin({
    required String title,
    required String subtitle,
  }) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: OledTheme.surfaceCard,
          title: Text(title, style: const TextStyle(fontSize: 15.5)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: OledTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Code PIN (6 chiffres)',
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(ctrl.text.trim()),
              child: const Text('Confirmer'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    return result;
  }

  /// SEC-11 : Rotation de clé isolée du Master PIN (`PRAGMA rekey`).
  Future<void> _openChangeMasterPinModal() async {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        String? error;
        bool busy = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: OledTheme.surfaceCard,
              title: const Text(
                'Rotation du Master PIN (PRAGMA rekey)',
                style: TextStyle(fontSize: 15.5),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: currentCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Master PIN actuel',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: newCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Nouveau Master PIN (6 chiffres)',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirmCtrl,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Confirmer le nouveau PIN',
                        counterText: '',
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: const TextStyle(
                          color: OledTheme.accentRed,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(ctx).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final nPin = newCtrl.text.trim();
                          if (nPin != confirmCtrl.text.trim()) {
                            setModalState(
                              () => error = 'La confirmation ne correspond pas.',
                            );
                            return;
                          }
                          setModalState(() {
                            busy = true;
                            error = null;
                          });
                          try {
                            await SecurityService.instance.changeMasterPin(
                              currentPin: currentCtrl.text.trim(),
                              newPin: nPin,
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop(true);
                          } catch (e) {
                            setModalState(() {
                              busy = false;
                              error = e
                                  .toString()
                                  .replaceFirst('Bad state: ', '')
                                  .replaceFirst('Invalid argument(s): ', '');
                            });
                          }
                        },
                  child: Text(busy ? 'Rekey...' : 'Appliquer'),
                ),
              ],
            );
          },
        );
      },
    );

    currentCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();

    if (changed == true && mounted) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Master PIN & clé SQLCipher AES-256 mis à jour.'),
        ),
      );
    }
  }

  /// SEC-05 : Configuration du Decoy PIN (Déni Plausible).
  Future<void> _openDecoyPinModal() async {
    final pin = await _promptSinglePin(
      title: 'Configurer le Decoy PIN (Déni Plausible)',
      subtitle:
          'Ce code à 6 chiffres (différent du Master PIN) ouvrira un coffre isolé innocent (sutura_decoy.db).',
    );
    if (pin == null || !mounted) return;

    try {
      await SecurityService.instance.setDecoyPin(pin);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _hasDecoyPin = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Decoy PIN configuré et isolé.')),
      );
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  /// SEC-12 : Protocole Panic Wipe armé par `DETRUIRE LE COFFRE`.
  Future<void> _openPanicWipeModal() async {
    final phraseCtrl = TextEditingController();

    final wiped = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        String? error;
        bool wiping = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: OledTheme.surfaceCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: OledTheme.accentRed, width: 1.5),
              ),
              title: const Row(
                children: [
                  Icon(Icons.local_fire_department, color: OledTheme.accentRed),
                  SizedBox(width: 8),
                  Text(
                    'PROTOCOLE PANIC WIPE',
                    style: TextStyle(
                      color: OledTheme.accentRed,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Auto-destruction anti-forensique irréversible : écrase toutes les bases (.db), journaux WAL/SHM et purge intégralement le Keystore matériel.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: OledTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Saisissez exactement : DETRUIRE LE COFFRE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: OledTheme.accentAmber,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phraseCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      hintText: PanicWipeService.confirmationPhrase,
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(
                        color: OledTheme.accentRed,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: wiping ? null : () => Navigator.of(ctx).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: OledTheme.accentRed,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: wiping
                      ? null
                      : () async {
                          final input = phraseCtrl.text.trim();
                          if (!PanicWipeService.isPhraseValid(input)) {
                            HapticFeedback.heavyImpact();
                            setModalState(
                              () => error = 'Phrase exacte requise.',
                            );
                            return;
                          }
                          setModalState(() {
                            wiping = true;
                            error = null;
                          });
                          await PanicWipeService.executePanicWipe(
                            phrase: input,
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop(true);
                        },
                  child: Text(wiping ? 'Destruction...' : 'EXÉCUTER'),
                ),
              ],
            );
          },
        );
      },
    );

    phraseCtrl.dispose();

    if (wiped == true && mounted) {
      Navigator.of(context).pop();
      widget.onVaultWiped();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hostileModeActive = !_biometricsAllowed;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Centre de Sécurité & Audit',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: OledTheme.accentEmerald),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
              children: [
                // 1. Centre d'Audit Temps Réel (Section 4.3)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Audit Disque Chiffré AES-256',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                                color: OledTheme.accentEmerald,
                              ),
                            ),
                            Text(
                              _formatSize(_dbSizeBytes),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace',
                                color: OledTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _AuditStat(label: 'Secrets', value: _counts.items),
                            _AuditStat(label: 'Docs', value: _counts.documents),
                            _AuditStat(label: 'Notes', value: _counts.notes),
                            _AuditStat(
                              label: 'Audio',
                              value: _counts.audioMemos,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => BackupRestoreScreen(
                                    onRestoreCompletedNeedRelock: () {
                                      Navigator.of(context)
                                        ..pop()
                                        ..pop();
                                      widget.onLockRequested();
                                    },
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.storage_rounded, size: 18),
                            label: const Text(
                              'Sauvegarde Flash & Restauration (.db)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // 2. Paramètres du Bouclier
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text(
                          'Scramble Pad (Clavier mélangé)',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Anti shoulder-surfing & anti traces de doigts (SEC-04)',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        activeThumbColor: OledTheme.accentEmerald, // Règle #6
                        value: _scramblePad,
                        onChanged: (v) async {
                          await SecurityService.instance
                              .setScramblePadEnabled(v);
                          if (mounted) setState(() => _scramblePad = v);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text(
                          'Mode Zone Hostile (PIN strict)',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Coupe la biométrie TEE et purge la clé matérielle (SEC-06)',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        activeThumbColor: OledTheme.accentAmber, // Règle #6
                        value: hostileModeActive,
                        onChanged: (v) => unawaited(_toggleHostileMode(v)),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: DropdownButtonFormField<int>(
                          initialValue: _autoLockSeconds,
                          isExpanded: true, // Règle #6
                          dropdownColor: OledTheme.surfaceCard,
                          decoration: const InputDecoration(
                            labelText: 'Verrouillage auto en arrière-plan (SEC-09)',
                          ),
                          items: const <DropdownMenuItem<int>>[
                            DropdownMenuItem<int>(
                              value: 0,
                              child: Text('Instantané (0 seconde)'),
                            ),
                            DropdownMenuItem<int>(
                              value: 15,
                              child: Text('Après 15 secondes'),
                            ),
                            DropdownMenuItem<int>(
                              value: 30,
                              child: Text('Après 30 secondes'),
                            ),
                            DropdownMenuItem<int>(
                              value: 60,
                              child: Text('Après 60 secondes'),
                            ),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            await SecurityService.instance
                                .setAutoLockTimeoutSeconds(v);
                            if (mounted) setState(() => _autoLockSeconds = v);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: DropdownButtonFormField<int>(
                          initialValue: _clipboardSeconds,
                          isExpanded: true, // Règle #6
                          dropdownColor: OledTheme.surfaceCard,
                          decoration: const InputDecoration(
                            labelText: 'Purge automatique du presse-papiers (SEC-10)',
                          ),
                          items: const <DropdownMenuItem<int>>[
                            DropdownMenuItem<int>(
                              value: 15,
                              child: Text('Après 15 secondes'),
                            ),
                            DropdownMenuItem<int>(
                              value: 30,
                              child: Text('Après 30 secondes'),
                            ),
                            DropdownMenuItem<int>(
                              value: 60,
                              child: Text('Après 60 secondes'),
                            ),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            await SecurityService.instance
                                .setClipboardPurgeSeconds(v);
                            if (mounted) setState(() => _clipboardSeconds = v);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // 3. Codes & Déni Plausible (masqué en session Decoy pour préserver SEC-05)
                if (!_isDecoySession)
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.key_rounded,
                            color: OledTheme.accentBlue,
                          ),
                          title: const Text(
                            'Changer le Master PIN',
                            style: TextStyle(fontSize: 14),
                          ),
                          subtitle: const Text(
                            'Rotation isolée SQLCipher PRAGMA rekey (SEC-11)',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => unawaited(_openChangeMasterPinModal()),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                            Icons.masks_outlined,
                            color: OledTheme.accentAmber,
                          ),
                          title: Text(
                            _hasDecoyPin
                                ? 'Modifier le Decoy PIN (Actif)'
                                : 'Configurer un Decoy PIN',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: const Text(
                            'Déni plausible via base isolée sutura_decoy.db (SEC-05)',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => unawaited(_openDecoyPinModal()),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 18),

                // 4. Zone Rouge : Protocole Panic Wipe (SEC-12)
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: OledTheme.accentRed.withValues(alpha: 0.65),
                    ),
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.local_fire_department_rounded,
                      color: OledTheme.accentRed,
                    ),
                    title: const Text(
                      'Protocole « Panic Wipe »',
                      style: TextStyle(
                        color: OledTheme.accentRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: const Text(
                      'Écrasement cryptographique Random.secure() & purge totale du Keystore',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    onTap: () => unawaited(_openPanicWipeModal()),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AuditStat extends StatelessWidget {
  const _AuditStat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: OledTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            color: OledTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}