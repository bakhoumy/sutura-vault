import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';

/// SEC-13 : Confirmation explicite rouge exigée avant toute suppression.
Future<bool> showDefensiveDeleteDialog(
  BuildContext context, {
  required String title,
  required String itemLabel,
}) async {
  HapticFeedback.heavyImpact();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) {
      return AlertDialog(
        backgroundColor: OledTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: OledTheme.accentRed.withValues(alpha: 0.6),
            width: 1.2,
          ),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: OledTheme.accentRed,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: OledTheme.accentRed,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Voulez-vous vraiment supprimer définitivement « $itemLabel » ?\nCette action est irréversible.',
          style: const TextStyle(
            color: OledTheme.textPrimary,
            fontSize: 13.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text(
              'Annuler',
              style: TextStyle(color: OledTheme.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: OledTheme.accentRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}