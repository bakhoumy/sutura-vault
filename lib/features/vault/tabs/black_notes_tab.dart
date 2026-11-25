import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';
import 'package:sutura_vault/core/utils/clipboard_vault.dart';
import 'package:sutura_vault/features/vault/models/vault_models.dart';
import 'package:sutura_vault/features/vault/repositories/vault_repository.dart';
import 'package:sutura_vault/features/vault/widgets/delete_confirm_dialog.dart';
import 'package:uuid/uuid.dart';

/// Compartiment 3 : Le Carnet des « Notes Noires » (Section 3.3).
class BlackNotesTab extends StatefulWidget {
  const BlackNotesTab({super.key});

  @override
  State<BlackNotesTab> createState() => _BlackNotesTabState();
}

class _BlackNotesTabState extends State<BlackNotesTab> {
  final TextEditingController _searchController = TextEditingController();
  List<BlackTextNote> _allNotes = <BlackTextNote>[];
  String _searchQuery = '';
  String _selectedDomain = 'Tous';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadNotes());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    final notes = await VaultRepository.instance.getAllNotes();
    if (!mounted) return;
    setState(() {
      _allNotes = notes;
      _isLoading = false;
    });
  }

  /// Règle #5 : Filtrage instantané en RAM (0 ms) sur titre, contenu et tags.
  List<BlackTextNote> get _filteredNotes {
    final q = _searchQuery.trim().toLowerCase();
    return _allNotes.where((note) {
      final matchesDomain =
          _selectedDomain == 'Tous' || note.category == _selectedDomain;
      if (!matchesDomain) return false;
      if (q.isEmpty) return true;
      return note.title.toLowerCase().contains(q) ||
          note.content.toLowerCase().contains(q) ||
          note.tags.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openEditor({BlackTextNote? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OledTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BlackNoteEditorSheet(existing: existing),
    );
    if (saved == true && mounted) {
      await _loadNotes();
    }
  }

  Future<void> _openViewer(BlackTextNote note) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _BlackNoteViewerScreen(
          note: note,
          onRequestEdit: () async {
            final saved = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              backgroundColor: OledTheme.surfaceDark,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => _BlackNoteEditorSheet(existing: note),
            );
            return saved ?? false;
          },
        ),
      ),
    );
    if (changed == true && mounted) {
      await _loadNotes();
    }
  }

  Future<void> _togglePin(BlackTextNote note) async {
    HapticFeedback.selectionClick();
    await VaultRepository.instance.toggleNotePin(
      note.id,
      isPinned: !note.isPinned,
    );
    if (mounted) await _loadNotes();
  }

  @override
  Widget build(BuildContext context) {
    final notes = _filteredNotes;
    final domains = <String>['Tous', ...BlackTextNote.domains];

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Rechercher titre, contenu, #tags...',
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
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: domains.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final domain = domains[index];
                final selected = domain == _selectedDomain;
                return ChoiceChip(
                  label: Text(domain, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  selectedColor: OledTheme.accentAmber.withValues(alpha: 0.2),
                  backgroundColor: OledTheme.surfaceCard,
                  side: BorderSide(
                    color: selected
                        ? OledTheme.accentAmber
                        : OledTheme.borderSubtle,
                  ),
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedDomain = domain);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: OledTheme.accentEmerald,
                    ),
                  )
                : notes.isEmpty
                    ? Center(
                        child: Text(
                          _allNotes.isEmpty
                              ? 'Aucune Note Noire.\nAppuyez sur + pour rédiger une note confidentielle.'
                              : 'Aucune note ne correspond à votre filtre.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: OledTheme.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                        itemCount: notes.length,
                        itemBuilder: (context, index) {
                          final note = notes[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              onTap: () => unawaited(_openViewer(note)),
                              leading: CircleAvatar(
                                backgroundColor: (note.isPinned
                                        ? OledTheme.accentAmber
                                        : OledTheme.accentBlue)
                                    .withValues(alpha: 0.16),
                                child: Icon(
                                  note.isPinned
                                      ? Icons.push_pin
                                      : Icons.description_outlined,
                                  size: 19,
                                  color: note.isPinned
                                      ? OledTheme.accentAmber
                                      : OledTheme.accentBlue,
                                ),
                              ),
                              title: Text(
                                note.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: OledTheme.textPrimary,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    note.category,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: OledTheme.accentEmerald,
                                    ),
                                  ),
                                  if (note.tags.isNotEmpty)
                                    Text(
                                      note.tags,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: OledTheme.textMuted,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: IconButton(
                                tooltip: note.isPinned
                                    ? 'Désépingler'
                                    : 'Épingler en priorité',
                                icon: Icon(
                                  note.isPinned
                                      ? Icons.push_pin
                                      : Icons.push_pin_outlined,
                                  size: 19,
                                  color: note.isPinned
                                      ? OledTheme.accentAmber
                                      : OledTheme.textMuted,
                                ),
                                onPressed: () => unawaited(_togglePin(note)),
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
        onPressed: () => unawaited(_openEditor()),
        child: const Icon(Icons.note_add_outlined),
      ),
    );
  }
}

class _BlackNoteViewerScreen extends StatefulWidget {
  const _BlackNoteViewerScreen({
    required this.note,
    required this.onRequestEdit,
  });

  final BlackTextNote note;
  final Future<bool> Function() onRequestEdit;

  @override
  State<_BlackNoteViewerScreen> createState() => _BlackNoteViewerScreenState();
}

class _BlackNoteViewerScreenState extends State<_BlackNoteViewerScreen> {
  /// Mode Discrétion Visuelle (Section 3.3) : masque instantanément en public.
  bool _discreetMode = false;

  Future<void> _copyContent() async {
    HapticFeedback.lightImpact();
    final seconds =
        await ClipboardVault.instance.copySecret(widget.note.content);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Contenu copié • Purge automatique dans ${seconds}s'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDefensiveDeleteDialog(
      context,
      title: 'Supprimer cette Note Noire ?',
      itemLabel: widget.note.title,
    );
    if (!confirmed) return;
    await VaultRepository.instance.deleteNote(widget.note.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return Scaffold(
      appBar: AppBar(
        title: Text(note.title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: _discreetMode
                ? 'Révéler la note'
                : 'Mode Discrétion Visuelle (masquer)',
            icon: Icon(
              _discreetMode
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: _discreetMode
                  ? OledTheme.accentAmber
                  : OledTheme.textSecondary,
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              setState(() => _discreetMode = !_discreetMode);
            },
          ),
          IconButton(
            tooltip: 'Copier (auto-purge)',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () => unawaited(_copyContent()),
          ),
          IconButton(
            tooltip: 'Modifier',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final saved = await widget.onRequestEdit();
              if (saved && context.mounted) {
                Navigator.of(context).pop(true);
              }
            },
          ),
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline, color: OledTheme.accentRed),
            onPressed: () => unawaited(_delete()),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  label: Text(note.category, style: const TextStyle(fontSize: 11.5)),
                  backgroundColor:
                      OledTheme.accentEmerald.withValues(alpha: 0.14),
                  side: BorderSide(
                    color: OledTheme.accentEmerald.withValues(alpha: 0.4),
                  ),
                ),
                if (note.tags.isNotEmpty)
                  Chip(
                    label: Text(note.tags, style: const TextStyle(fontSize: 11.5)),
                    backgroundColor: OledTheme.surfaceCard,
                    side: const BorderSide(color: OledTheme.borderSubtle),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: OledTheme.surfaceCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _discreetMode
                      ? OledTheme.accentAmber.withValues(alpha: 0.45)
                      : OledTheme.borderSubtle,
                ),
              ),
              child: SelectableText(
                _discreetMode
                    ? '••••••••••••••••••••••••••••••••••••\n••••••••••••••••••••••••••••••\n(Mode Discrétion Visuelle actif)'
                    : note.content,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.55,
                  fontFamily: _discreetMode ? 'monospace' : null,
                  color: _discreetMode
                      ? OledTheme.accentAmber
                      : OledTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlackNoteEditorSheet extends StatefulWidget {
  const _BlackNoteEditorSheet({this.existing});
  final BlackTextNote? existing;

  @override
  State<_BlackNoteEditorSheet> createState() => _BlackNoteEditorSheetState();
}

class _BlackNoteEditorSheetState extends State<_BlackNoteEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _tagsCtrl;
  late final TextEditingController _contentCtrl;
  late String _domain;
  late bool _isPinned;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _tagsCtrl = TextEditingController(text: e?.tags ?? '');
    _contentCtrl = TextEditingController(text: e?.content ?? '');
    _domain = e?.category ?? BlackTextNote.domains.first;
    _isPinned = e?.isPinned ?? false;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _tagsCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  String _autoTimestampTitle() {
    final now = DateTime.now();
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return 'Note Noire — $d/$m/${now.year} $h:$min';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    setState(() => _isSaving = true);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final resolvedTitle = _titleCtrl.text.trim().isEmpty
        ? _autoTimestampTitle()
        : _titleCtrl.text.trim();

    final note = BlackTextNote(
      id: widget.existing?.id ?? const Uuid().v4(),
      title: resolvedTitle,
      content: _contentCtrl.text,
      category: _domain,
      tags: _tagsCtrl.text.trim(),
      isPinned: _isPinned,
      createdAt: widget.existing?.createdAt ?? nowMs,
      updatedAt: nowMs,
    );

    await VaultRepository.instance.upsertNote(note);
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
              Text(
                widget.existing == null
                    ? 'Nouvelle Note Noire'
                    : 'Modifier la Note Noire',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: OledTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Titre (auto-horodaté si laissé vide)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _domain,
                isExpanded: true, // Règle #6 obligatoire
                decoration: const InputDecoration(labelText: 'Domaine'),
                dropdownColor: OledTheme.surfaceCard,
                items: BlackTextNote.domains
                    .map(
                      (d) => DropdownMenuItem<String>(
                        value: d,
                        child: Text(d, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _domain = v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tagsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mots-clés / Tags (ex: #contrat #ssh #urgence)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contentCtrl,
                maxLines: 7,
                decoration: const InputDecoration(
                  labelText: 'Contenu confidentiel (Texte / Markdown / Code) *',
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Contenu requis'
                    : null,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Épingler en haut de la liste',
                  style: TextStyle(fontSize: 13.5),
                ),
                activeThumbColor: OledTheme.accentEmerald, // Règle #6
                value: _isPinned,
                onChanged: (v) => setState(() => _isPinned = v),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: OledTheme.accentEmerald,
                  foregroundColor: OledTheme.bgPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isSaving ? null : () => unawaited(_save()),
                child: Text(
                  _isSaving ? 'Scellement...' : 'Sceller la Note Noire',
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