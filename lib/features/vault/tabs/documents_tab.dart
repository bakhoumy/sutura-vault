import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sutura_vault/core/security/security_guard.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';
import 'package:sutura_vault/features/vault/models/vault_models.dart';
import 'package:sutura_vault/features/vault/repositories/vault_repository.dart';
import 'package:sutura_vault/features/vault/widgets/delete_confirm_dialog.dart';
import 'package:uuid/uuid.dart';

/// Compartiment 2 : Porte-Documents Numérique Chiffré (Section 3.2).
class DocumentsTab extends StatefulWidget {
  const DocumentsTab({super.key});

  @override
  State<DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<DocumentsTab> {
  final TextEditingController _searchController = TextEditingController();
  List<VaultDocument> _allDocs = <VaultDocument>[];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDocuments());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    final docs = await VaultRepository.instance.getAllDocuments();
    if (!mounted) return;
    setState(() {
      _allDocs = docs;
      _isLoading = false;
    });
  }

  List<VaultDocument> get _filteredDocs {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _allDocs;
    return _allDocs.where((doc) {
      return doc.title.toLowerCase().contains(q) ||
          doc.docType.toLowerCase().contains(q) ||
          doc.notes.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openAddSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OledTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _DocumentAddSheet(),
    );
    if (added == true && mounted) {
      await _loadDocuments();
    }
  }

  Future<void> _openViewer(VaultDocument doc) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _SecureDocumentViewerScreen(document: doc),
      ),
    );
    if (deleted == true && mounted) {
      await _loadDocuments();
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = _filteredDocs;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Rechercher CNI, Passeport, NINEA, Contrat...',
                prefixIcon: const Icon(
                  Icons.search,
                  color: OledTheme.textMuted,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: OledTheme.accentEmerald,
                    ),
                  )
                : docs.isEmpty
                    ? Center(
                        child: Text(
                          _allDocs.isEmpty
                              ? 'Aucun document chiffré.\nAppuyez sur + pour scanner ou importer un document.'
                              : 'Aucun document trouvé.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: OledTheme.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              onTap: () => unawaited(_openViewer(doc)),
                              leading: CircleAvatar(
                                backgroundColor:
                                    OledTheme.accentBlue.withValues(alpha: 0.16),
                                child: const Icon(
                                  Icons.badge_outlined,
                                  size: 20,
                                  color: OledTheme.accentBlue,
                                ),
                              ),
                              title: Text(
                                doc.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: OledTheme.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                doc.docType,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: OledTheme.textSecondary,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.zoom_in_rounded,
                                color: OledTheme.textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, // Règle #6
        backgroundColor: OledTheme.accentEmerald,
        foregroundColor: OledTheme.bgPrimary,
        onPressed: () => unawaited(_openAddSheet()),
        child: const Icon(Icons.add_a_photo_outlined),
      ),
    );
  }
}

class _DocumentAddSheet extends StatefulWidget {
  const _DocumentAddSheet();

  @override
  State<_DocumentAddSheet> createState() => _DocumentAddSheetState();
}

class _DocumentAddSheetState extends State<_DocumentAddSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _customTypeCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String _selectedType = VaultDocument.predefinedTypes.first;
  Uint8List? _imageBytes;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _customTypeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// Capture caméra/galerie protégée par SecurityGuard + compression 1080p / 75%.
  Future<void> _pickImage(ImageSource source) async {
    final picked = await SecurityGuard.instance.runProtected<XFile?>(() async {
      return _picker.pickImage(
        source: source,
        maxWidth: 1080,
        imageQuality: 75,
      );
    });
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _imageBytes = bytes);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    if (_imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Capturez ou importez d\'abord la photo du document.'),
        ),
      );
      return;
    }

    final resolvedType = _selectedType == 'Autre' &&
            _customTypeCtrl.text.trim().isNotEmpty
        ? _customTypeCtrl.text.trim()
        : _selectedType;

    setState(() => _isSaving = true);
    final doc = VaultDocument(
      id: const Uuid().v4(),
      title: _titleCtrl.text.trim(),
      docType: resolvedType,
      imageBase64: base64Encode(_imageBytes!),
      notes: _notesCtrl.text.trim(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await VaultRepository.instance.insertDocument(doc);
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
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Sceller un Document Officiel',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: OledTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => unawaited(_pickImage(ImageSource.camera)),
                      icon: const Icon(Icons.camera_alt_outlined, size: 18),
                      label: const Text('Caméra'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          unawaited(_pickImage(ImageSource.gallery)),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Galerie'),
                    ),
                  ),
                ],
              ),
              if (_imageBytes != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _imageBytes!,
                    height: 140,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Titre du document *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Titre requis' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                isExpanded: true, // Règle #6 obligatoire
                decoration: const InputDecoration(labelText: 'Type de document'),
                dropdownColor: OledTheme.surfaceCard,
                items: VaultDocument.predefinedTypes
                    .map(
                      (t) => DropdownMenuItem<String>(
                        value: t,
                        child: Text(t, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedType = v);
                },
              ),
              if (_selectedType == 'Autre') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customTypeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Type personnalisé (libre)',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes / Numéro de référence',
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: OledTheme.accentEmerald,
                  foregroundColor: OledTheme.bgPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isSaving ? null : () => unawaited(_save()),
                child: Text(
                  _isSaving ? 'Chiffrement...' : 'Sceller dans SQLCipher',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Visionneuse Haute Sécurité (Zoom x4, FLAG_SECURE, Export / Partage sous SecurityGuard).
class _SecureDocumentViewerScreen extends StatelessWidget {
  const _SecureDocumentViewerScreen({required this.document});

  final VaultDocument document;

  Future<void> _shareDocument(BuildContext context, Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final safeName =
        document.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final tempFile = File(p.join(tempDir.path, 'sutura_doc_$safeName.jpg'));
    await tempFile.writeAsBytes(bytes, flush: true);

    try {
      await SecurityGuard.instance.runProtected<void>(() async {
        await Share.shareXFiles(
          <XFile>[XFile(tempFile.path)],
          text: document.title,
        );
      });
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<void> _exportToDownloads(BuildContext context, Uint8List bytes) async {
    final safeName =
        document.title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final downloadDir = Directory('/storage/emulated/0/Download');
    final targetDir = await downloadDir.exists()
        ? downloadDir
        : await getApplicationDocumentsDirectory();

    final outFile = File(
      p.join(targetDir.path, 'sutura_${safeName}_$timestamp.jpg'),
    );
    await outFile.writeAsBytes(bytes, flush: true);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exporté vers : ${outFile.path}')),
    );
  }

  Future<void> _deleteDocument(BuildContext context) async {
    final confirmed = await showDefensiveDeleteDialog(
      context,
      title: 'Supprimer ce document ?',
      itemLabel: document.title,
    );
    if (!confirmed) return;

    await VaultRepository.instance.deleteDocument(document.id);
    if (!context.mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = base64Decode(document.imageBase64);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(document.title, style: const TextStyle(fontSize: 15)),
            Text(
              document.docType,
              style: const TextStyle(
                fontSize: 11.5,
                color: OledTheme.accentBlue,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Télécharger dans Download',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => unawaited(_exportToDownloads(context, bytes)),
          ),
          IconButton(
            tooltip: 'Partager / Imprimer',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => unawaited(_shareDocument(context, bytes)),
          ),
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline, color: OledTheme.accentRed),
            onPressed: () => unawaited(_deleteDocument(context)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: Center(
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ),
          if (document.notes.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: OledTheme.surfaceDark,
              child: Text(
                document.notes,
                style: const TextStyle(
                  color: OledTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}