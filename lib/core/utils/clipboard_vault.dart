import 'dart:async';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/security/security_service.dart';

/// Presse-papiers éphémère à purge automatique (SEC-10).
class ClipboardVault {
  ClipboardVault._internal();
  static final ClipboardVault instance = ClipboardVault._internal();

  Timer? _purgeTimer;
  String? _lastCopiedSecret;

  /// Copie un secret et programme son effacement automatique.
  /// Retourne le délai effectif en secondes (pour retour visuel SnackBar).
  Future<int> copySecret(String secret, {int? overrideSeconds}) async {
    _purgeTimer?.cancel();

    final seconds = overrideSeconds ??
        await SecurityService.instance.getClipboardPurgeSeconds();

    await Clipboard.setData(ClipboardData(text: secret));
    _lastCopiedSecret = secret;

    _purgeTimer = Timer(Duration(seconds: seconds), () {
      unawaited(_purgeIfUnchanged());
    });

    return seconds;
  }

  Future<void> _purgeIfUnchanged() async {
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == _lastCopiedSecret) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: ''));
    } finally {
      _lastCopiedSecret = null;
      _purgeTimer = null;
    }
  }

  /// Effacement immédiat (verrouillage du coffre ou Panic Wipe).
  Future<void> purgeNow() async {
    _purgeTimer?.cancel();
    _purgeTimer = null;
    _lastCopiedSecret = null;
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {}
  }
}