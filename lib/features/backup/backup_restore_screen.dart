import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sutura_vault/core/theme/oled_theme.dart';
import 'package:sutura_vault/features/backup/backup_service.dart';

/// Écran de Sauvegarde Directe (.db) & Restauration en Bac à Sable (Section 4).
class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({
    required this.onRestoreCompletedNeedRelock,
    super.key,
  });

  final VoidCallback onRestoreCompletedNeedRelock;

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  static const Map<String, String> _shortcuts = <String, String>{
    'Download': '/storage/emulated/0/Download',
    'Interne': '/storage/emulated/0',
    'Documents': '/storage/emulated/0/Documents',
    'SD / USB OTG': '/storage',
  };

  bool _isExporting = false;
  File? _lastExportedFile;

  String _currentPath = '/storage/emulated/0/Download';
  List<FileSystemEntity> _entries = <FileSystemEntity>[];
  String? _browserStatus;

  @override
  void initState() {
    super.initState();
    unawaited(_browse(_currentPath));
  }

  Future<void> _exportNow() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final exported = await BackupService.exportEncryptedBackup();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _lastExportedFile = exported;
        _isExporting = false;
      });
      await _browse(_currentPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sauvegarde AES-256 créée : ${p.basename(exported.path)}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur d\'export : $e')),
      );
    }
  }

  Future<void> _browse(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      if (!mounted) return;
      setState(() {
        _currentPath = dirPath;
        _entries = <FileSystemEntity>[];
        _browserStatus = 'Dossier introuvable : $dirPath';
      });
      return;
    }

    try {
      final list = await dir.list(followLinks: false).toList();
      final filtered = list.where((entity) {
        final name = p.basename(entity.path);
        if (entity is Directory) return !name.startsWith('.');
        if (entity is File) return name.toLowerCase().endsWith('.db');
        return false;
      }).toList()
        ..sort((a, b) {
          if (a is Directory && b is! Directory) return -1;
          if (a is! Directory && b is Directory) return 1;
          return p.basename(a.path).toLowerCase().compareTo(
                p.basename(b.path).toLowerCase(),
              );
        });

      if (!mounted) return;
      setState(() {
        _currentPath = dirPath;
        _entries = filtered;
        _browserStatus =
            filtered.isEmpty ? 'Aucun fichier .db trouvé dans ce dossier.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentPath = dirPath;
        _entries = <FileSystemEntity>[];
        _browserStatus = 'Accès restreint sur ce dossier par le système.';
      });
    }
  }

  Future<void> _openSandboxRestoreDialog(File dbFile) async {
    final restored = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SandboxRestoreDialog(backupFile: dbFile),
    );

    if (restored == true && mounted) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Restauration validée en bac à sable ! Reconnexion sécurisée...',
          ),
        ),
      );
      widget.onRestoreCompletedNeedRelock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Sauvegarde & Restauration (.db)',
          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          // Carte Sauvegarde Directe AES-256
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.save_alt_rounded,
                          color: OledTheme.accentEmerald,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Sauvegarde Directe Chiffrée (.db)',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: OledTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Exécute PRAGMA wal_checkpoint(FULL) puis copie la base déjà chiffrée AES-256 vers Download.',
                      style: TextStyle(
                        fontSize: 12,
                        color: OledTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: OledTheme.accentEmerald,
                              foregroundColor: OledTheme.bgPrimary,
                            ),
                            onPressed: _isExporting
                                ? null
                                : () => unawaited(_exportNow()),
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: Text(
                              _isExporting ? 'Export...' : 'Exporter .db',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        if (_lastExportedFile != null) ...[
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () => unawaited(
                              BackupService.shareBackupFile(_lastExportedFile!),
                            ),
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: const Text('Partager'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // En-tête Explorateur Souverain (.db)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Restauration en Bac à Sable (Explorateur Souverain dart:io)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: OledTheme.accentBlue,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _shortcuts.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(
                            entry.key,
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          backgroundColor: OledTheme.surfaceCard,
                          onPressed: () => unawaited(_browse(entry.value)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Dossier parent',
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      onPressed: () {
                        final parent = Directory(_currentPath).parent.path;
                        if (parent != _currentPath) {
                          unawaited(_browse(parent));
                        }
                      },
                    ),
                    Expanded(
                      child: Text(
                        _currentPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: OledTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _browserStatus != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _browserStatus!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: OledTheme.textSecondary),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entity = _entries[index];
                      final isDir = entity is Directory;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isDir
                              ? Icons.folder_outlined
                              : Icons.storage_rounded,
                          color: isDir
                              ? OledTheme.accentAmber
                              : OledTheme.accentEmerald,
                        ),
                        title: Text(
                          p.basename(entity.path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: !isDir
                            ? const Text(
                                'Appuyer pour tester & restaurer en bac à sable',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: OledTheme.textMuted,
                                ),
                              )
                            : null,
                        onTap: () {
                          if (isDir) {
                            unawaited(_browse(entity.path));
                          } else if (entity is File) {
                            unawaited(_openSandboxRestoreDialog(entity));
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SandboxRestoreDialog extends StatefulWidget {
  const _SandboxRestoreDialog({required this.backupFile});
  final File backupFile;

  @override
  State<_SandboxRestoreDialog> createState() => _SandboxRestoreDialogState();
}

class _SandboxRestoreDialogState extends State<_SandboxRestoreDialog> {
  final TextEditingController _archivePinCtrl = TextEditingController();
  final TextEditingController _currentPinCtrl = TextEditingController();
  bool _obscureArchivePin = true;
  bool _obscureCurrentPin = true;
  bool _isRestoring = false;
  String? _errorText;

  @override
  void dispose() {
    _archivePinCtrl.dispose();
    _currentPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _executeRestore() async {
    if (_isRestoring) return;
    setState(() {
      _isRestoring = true;
      _errorText = null;
    });

    try {
      await BackupService.restoreFromBackup(
        backupFile: widget.backupFile,
        archivePin: _archivePinCtrl.text.trim(),
        currentDevicePin: _currentPinCtrl.text.trim().isEmpty
            ? null
            : _currentPinCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _isRestoring = false;
        _errorText = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: OledTheme.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: OledTheme.accentBlue.withValues(alpha: 0.5),
        ),
      ),
      title: const Text(
        'Test & Restauration en Bac à Sable',
        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Archive : ${p.basename(widget.backupFile.path)}',
              style: const TextStyle(
                fontSize: 12,
                color: OledTheme.accentEmerald,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Votre base actuelle n\'est jamais modifiée tant que le déchiffrement SQLCipher n\'est pas validé.',
              style: TextStyle(fontSize: 12, color: OledTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _archivePinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: _obscureArchivePin,
              decoration: InputDecoration(
                labelText: 'Master PIN de l\'archive (6 chiffres) *',
                counterText: '',
                suffixIcon: IconButton(
                  tooltip: 'Vérifier le PIN',
                  icon: Icon(
                    _obscureArchivePin
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscureArchivePin = !_obscureArchivePin),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _currentPinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: _obscureCurrentPin,
              decoration: InputDecoration(
                labelText: 'PIN actuel du téléphone (si différent, rekey auto)',
                counterText: '',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureCurrentPin
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscureCurrentPin = !_obscureCurrentPin),
                ),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorText!,
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
          onPressed: _isRestoring ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: OledTheme.accentEmerald,
            foregroundColor: OledTheme.bgPrimary,
          ),
          onPressed: _isRestoring ? null : () => unawaited(_executeRestore()),
          child: Text(_isRestoring ? 'Validation...' : 'Valider & Restaurer'),
        ),
      ],
    );
  }
}