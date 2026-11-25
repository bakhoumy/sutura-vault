import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sutura_vault/core/security/panic_wipe_service.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';
import 'package:sutura_vault/features/vault/models/vault_models.dart';
import 'package:sutura_vault/features/vault/repositories/vault_repository.dart';
import 'package:sutura_vault/features/vault/widgets/delete_confirm_dialog.dart';
import 'package:uuid/uuid.dart';

/// Compartiment 4 : Studio de Mémos Vocaux Noirs (Section 3.4).
class BlackAudioTab extends StatefulWidget {
  const BlackAudioTab({super.key});

  @override
  State<BlackAudioTab> createState() => _BlackAudioTabState();
}

class _BlackAudioTabState extends State<BlackAudioTab> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  List<BlackAudioMemo> _memos = <BlackAudioMemo>[];
  bool _isLoading = true;
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _tempRecordingPath;

  String? _playingMemoId;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMemos());
    _completeSub = _player.onPlayerComplete.listen((_) {
      unawaited(_handlePlaybackComplete());
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    unawaited(_completeSub?.cancel());
    unawaited(_player.dispose());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _loadMemos() async {
    final list = await VaultRepository.instance.getAllAudioMemos();
    if (!mounted) return;
    setState(() {
      _memos = list;
      _isLoading = false;
    });
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopAndSealRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission microphone requise.')),
      );
      return;
    }

    if (_playingMemoId != null) {
      await _player.stop();
      setState(() => _playingMemoId = null);
    }

    final tempDir = await getTemporaryDirectory();
    final path = p.join(
      tempDir.path,
      'sutura_tmp_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );

    HapticFeedback.mediumImpact();
    setState(() {
      _isRecording = true;
      _recordSeconds = 0;
      _tempRecordingPath = path;
    });

    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });
  }

  /// Lit le fichier temporaire en RAM, détruit immédiatement le fichier disque,
  /// puis demande titre & protocole d'auto-destruction pour scellement SQLCipher.
  Future<void> _stopAndSealRecording() async {
    _recordTimer?.cancel();
    final duration = _recordSeconds < 1 ? 1 : _recordSeconds;
    final recordedPath = await _recorder.stop() ?? _tempRecordingPath;

    setState(() {
      _isRecording = false;
      _recordSeconds = 0;
      _tempRecordingPath = null;
    });

    if (recordedPath == null) return;
    final tempFile = File(recordedPath);
    if (!await tempFile.exists()) return;

    final bytes = await tempFile.readAsBytes();
    // Destruction physique immédiate du fichier temporaire disque (Section 3.4)
    await PanicWipeService.shredFile(tempFile);

    if (!mounted || bytes.isEmpty) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OledTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SealAudioSheet(
        audioBytes: bytes,
        durationSeconds: duration,
      ),
    );
    if (saved == true && mounted) {
      await _loadMemos();
    }
  }

  /// Lecture exclusive en mémoire vive (BytesSource — zéro réécriture disque).
  Future<void> _togglePlay(BlackAudioMemo memo) async {
    if (_isRecording) return;

    if (_playingMemoId == memo.id) {
      await _player.stop();
      setState(() => _playingMemoId = null);
      return;
    }

    await _player.stop();
    final bytes = base64Decode(memo.audioBase64);
    HapticFeedback.lightImpact();

    setState(() => _playingMemoId = memo.id);
    await _player.play(BytesSource(bytes));
  }

  Future<void> _handlePlaybackComplete() async {
    final finishedId = _playingMemoId;
    if (finishedId == null) return;

    BlackAudioMemo? finishedMemo;
    for (final m in _memos) {
      if (m.id == finishedId) {
        finishedMemo = m;
        break;
      }
    }

    if (mounted) {
      setState(() => _playingMemoId = null);
    }

    if (finishedMemo == null) return;

    if (finishedMemo.autoDeleteMode == AudioAutoDeleteMode.burnAfterListening) {
      // 🔥 Burn After Listening : suppression automatique immédiate de la base
      await VaultRepository.instance.deleteAudioMemo(finishedMemo.id);
      if (mounted) {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🔥 « ${finishedMemo.title} » (Écoute Unique) auto-détruit.',
            ),
          ),
        );
        await _loadMemos();
      }
    } else {
      await VaultRepository.instance.incrementAudioListenCount(finishedMemo.id);
      if (mounted) await _loadMemos();
    }
  }

  Future<void> _openSovereignAudioImporter() async {
    final imported = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OledTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _SovereignAudioImportSheet(),
    );
    if (imported == true && mounted) {
      await _loadMemos();
    }
  }

  Future<void> _deleteMemo(BlackAudioMemo memo) async {
    final confirmed = await showDefensiveDeleteDialog(
      context,
      title: 'Supprimer ce mémo vocal ?',
      itemLabel: memo.title,
    );
    if (!confirmed) return;

    if (_playingMemoId == memo.id) {
      await _player.stop();
      if (mounted) setState(() => _playingMemoId = null);
    }
    await VaultRepository.instance.deleteAudioMemo(memo.id);
    if (mounted) await _loadMemos();
  }

  String _formatDuration(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Color _modeColor(AudioAutoDeleteMode mode) {
    switch (mode) {
      case AudioAutoDeleteMode.permanent:
        return OledTheme.accentEmerald;
      case AudioAutoDeleteMode.burnAfterListening:
        return OledTheme.accentRed;
      case AudioAutoDeleteMode.ephemeral24h:
        return OledTheme.accentAmber;
    }
  }

  IconData _modeIcon(AudioAutoDeleteMode mode) {
    switch (mode) {
      case AudioAutoDeleteMode.permanent:
        return Icons.shield_outlined;
      case AudioAutoDeleteMode.burnAfterListening:
        return Icons.local_fire_department_outlined;
      case AudioAutoDeleteMode.ephemeral24h:
        return Icons.hourglass_bottom_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Console de dictée éclair en 1 clic + Import souverain
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: OledTheme.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isRecording
                    ? OledTheme.accentRed.withValues(alpha: 0.7)
                    : OledTheme.borderSubtle,
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => unawaited(_toggleRecording()),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording
                          ? OledTheme.accentRed
                          : OledTheme.accentEmerald,
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: _isRecording ? Colors.white : OledTheme.bgPrimary,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isRecording
                            ? 'Enregistrement AAC 64kbps...'
                            : 'Dictée Éclair (1 clic)',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: _isRecording
                              ? OledTheme.accentRed
                              : OledTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _isRecording
                            ? 'Durée : ${_formatDuration(_recordSeconds)} • Appuyez pour sceller'
                            : 'Lecture RAM pure • Zéro trace disque',
                        style: const TextStyle(
                          fontSize: 12,
                          color: OledTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isRecording)
                  IconButton(
                    tooltip: 'Importer audio (Explorateur Souverain)',
                    icon: const Icon(
                      Icons.folder_open_outlined,
                      color: OledTheme.accentBlue,
                    ),
                    onPressed: () => unawaited(_openSovereignAudioImporter()),
                  ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: OledTheme.accentEmerald,
                    ),
                  )
                : _memos.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucun mémo vocal scellé.\nDictez en 1 clic ou importez un fichier audio.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: OledTheme.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                        itemCount: _memos.length,
                        itemBuilder: (context, index) {
                          final memo = _memos[index];
                          final isPlaying = _playingMemoId == memo.id;
                          final modeColor = _modeColor(memo.autoDeleteMode);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: IconButton(
                                icon: Icon(
                                  isPlaying
                                      ? Icons.stop_circle_outlined
                                      : Icons.play_circle_outline,
                                  size: 32,
                                  color: isPlaying
                                      ? OledTheme.accentAmber
                                      : OledTheme.accentEmerald,
                                ),
                                onPressed: () => unawaited(_togglePlay(memo)),
                              ),
                              title: Text(
                                memo.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: OledTheme.textPrimary,
                                ),
                              ),
                              subtitle: Row(
                                children: [
                                  Icon(
                                    _modeIcon(memo.autoDeleteMode),
                                    size: 13,
                                    color: modeColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${memo.autoDeleteMode.label} • ${_formatDuration(memo.durationSeconds)}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: modeColor,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                tooltip: 'Supprimer',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: OledTheme.accentRed,
                                  size: 20,
                                ),
                                onPressed: () => unawaited(_deleteMemo(memo)),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SealAudioSheet extends StatefulWidget {
  const _SealAudioSheet({
    required this.audioBytes,
    required this.durationSeconds,
    this.defaultTitle,
    this.sourceFileToShred,
  });

  final Uint8List audioBytes;
  final int durationSeconds;
  final String? defaultTitle;
  final File? sourceFileToShred;

  @override
  State<_SealAudioSheet> createState() => _SealAudioSheetState();
}

class _SealAudioSheetState extends State<_SealAudioSheet> {
  late final TextEditingController _titleCtrl;
  AudioAutoDeleteMode _mode = AudioAutoDeleteMode.permanent;
  bool _shredOriginal = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    _titleCtrl = TextEditingController(
      text: widget.defaultTitle ??
          'Mémo Vocal — ${now.day}/${now.month} $h:$min',
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _seal() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final memo = BlackAudioMemo(
      id: const Uuid().v4(),
      title: _titleCtrl.text.trim().isEmpty
          ? 'Mémo Vocal Noir'
          : _titleCtrl.text.trim(),
      durationSeconds: widget.durationSeconds,
      audioBase64: base64Encode(widget.audioBytes),
      autoDeleteMode: _mode,
      listenCount: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await VaultRepository.instance.insertAudioMemo(memo);

    // Shredder source si coché lors d'un import (Section 3.4)
    if (_shredOriginal && widget.sourceFileToShred != null) {
      await PanicWipeService.shredFile(widget.sourceFileToShred!);
    }

    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sceller le Mémo Vocal Noir',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: OledTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Titre du mémo'),
            ),
            const SizedBox(height: 14),
            const Text(
              'Protocole d\'auto-destruction',
              style: TextStyle(
                fontSize: 12.5,
                color: OledTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<AudioAutoDeleteMode>(
              initialValue: _mode,
              isExpanded: true, // Règle #6 obligatoire
              dropdownColor: OledTheme.surfaceCard,
              items: AudioAutoDeleteMode.values
                  .map(
                    (m) => DropdownMenuItem<AudioAutoDeleteMode>(
                      value: m,
                      child: Text(m.label, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _mode = v);
              },
            ),
            if (widget.sourceFileToShred != null) ...[
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Détruire le fichier original (Shredder)',
                  style: TextStyle(fontSize: 13, color: OledTheme.accentRed),
                ),
                subtitle: const Text(
                  'Écrase puis supprime le fichier public après scellement',
                  style: TextStyle(fontSize: 11.5),
                ),
                activeThumbColor: OledTheme.accentRed, // Règle #6
                value: _shredOriginal,
                onChanged: (v) => setState(() => _shredOriginal = v),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: OledTheme.accentEmerald,
                foregroundColor: OledTheme.bgPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isSaving ? null : () => unawaited(_seal()),
              child: Text(
                _isSaving ? 'Scellement...' : 'Sceller en AES-256',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explorateur Audio Souverain 100 % dart:io (Règle #4 : zéro file_picker).
class _SovereignAudioImportSheet extends StatefulWidget {
  const _SovereignAudioImportSheet();

  @override
  State<_SovereignAudioImportSheet> createState() =>
      _SovereignAudioImportSheetState();
}

class _SovereignAudioImportSheetState extends State<_SovereignAudioImportSheet> {
  static const Set<String> _supportedExts = <String>{
    '.mp3',
    '.m4a',
    '.wav',
    '.aac',
    '.ogg',
    '.opus',
    '.amr',
  };

  static const Map<String, String> _shortcuts = <String, String>{
    'Enregistrements': '/storage/emulated/0/Recordings',
    'Téléchargements': '/storage/emulated/0/Download',
    'Musique': '/storage/emulated/0/Music',
    'WhatsApp Audio':
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio',
  };

  String _currentPath = '/storage/emulated/0/Download';
  List<FileSystemEntity> _entries = <FileSystemEntity>[];
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_browse(_currentPath));
  }

  Future<void> _browse(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      if (!mounted) return;
      setState(() {
        _currentPath = dirPath;
        _entries = <FileSystemEntity>[];
        _statusMessage = 'Dossier introuvable : $dirPath';
      });
      return;
    }

    try {
      final list = await dir.list(followLinks: false).toList();
      final filtered = list.where((e) {
        if (e is Directory) return !p.basename(e.path).startsWith('.');
        if (e is File) {
          return _supportedExts.contains(p.extension(e.path).toLowerCase());
        }
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
        _statusMessage =
            filtered.isEmpty ? 'Aucun fichier audio dans ce dossier.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentPath = dirPath;
        _entries = <FileSystemEntity>[];
        _statusMessage =
            'Accès refusé par Android sur ce dossier (vérifiez les permissions média).';
      });
    }
  }

  Future<void> _selectFile(File file) async {
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final sealed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OledTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SealAudioSheet(
        audioBytes: bytes,
        durationSeconds: 0,
        defaultTitle: p.basenameWithoutExtension(file.path),
        sourceFileToShred: file,
      ),
    );

    if (sealed == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Explorateur Audio Souverain (dart:io)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: OledTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _shortcuts.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(entry.key, style: const TextStyle(fontSize: 11.5)),
                      backgroundColor: OledTheme.surfaceCard,
                      onPressed: () => unawaited(_browse(entry.value)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  tooltip: 'Dossier parent',
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: () {
                    final parent = Directory(_currentPath).parent.path;
                    if (parent != _currentPath) unawaited(_browse(parent));
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
            const Divider(height: 8),
            Expanded(
              child: _statusMessage != null
                  ? Center(
                      child: Text(
                        _statusMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: OledTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entity = _entries[index];
                        final isDir = entity is Directory;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isDir ? Icons.folder_outlined : Icons.audio_file_outlined,
                            color: isDir
                                ? OledTheme.accentAmber
                                : OledTheme.accentEmerald,
                          ),
                          title: Text(
                            p.basename(entity.path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            if (isDir) {
                              unawaited(_browse(entity.path));
                            } else if (entity is File) {
                              unawaited(_selectFile(entity));
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}