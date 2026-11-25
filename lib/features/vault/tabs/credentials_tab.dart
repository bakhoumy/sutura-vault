import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';
import 'package:sutura_vault/core/utils/clipboard_vault.dart';
import 'package:sutura_vault/core/utils/password_generator.dart';
import 'package:sutura_vault/features/vault/models/vault_models.dart';
import 'package:sutura_vault/features/vault/repositories/vault_repository.dart';
import 'package:sutura_vault/features/vault/widgets/delete_confirm_dialog.dart';
import 'package:uuid/uuid.dart';

/// Compartiment 1 : Gestionnaire d'Identifiants, Clés IT & Secrets (Section 3.1).
class CredentialsTab extends StatefulWidget {
  const CredentialsTab({super.key});

  @override
  State<CredentialsTab> createState() => _CredentialsTabState();
}

class _CredentialsTabState extends State<CredentialsTab> {
  final TextEditingController _searchController = TextEditingController();
  List<VaultItem> _allItems = <VaultItem>[];
  String _searchQuery = '';
  String _selectedCategory = 'Toutes';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadItems());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final items = await VaultRepository.instance.getAllItems();
    if (!mounted) return;
    setState(() {
      _allItems = items;
      _isLoading = false;
    });
  }

  /// Règle #5 : Filtrage instantané en RAM (0 ms, zéro appel DB dans onChanged).
  List<VaultItem> get _filteredItems {
    final q = _searchQuery.trim().toLowerCase();
    return _allItems.where((item) {
      final matchesCat =
          _selectedCategory == 'Toutes' || item.category == _selectedCategory;
      if (!matchesCat) return false;
      if (q.isEmpty) return true;
      return item.title.toLowerCase().contains(q) ||
          item.login.toLowerCase().contains(q) ||
          item.url.toLowerCase().contains(q) ||
          item.notes.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _copyWithAutoPurge(String label, String secret) async {
    if (secret.isEmpty) return;
    HapticFeedback.lightImpact();
    final purgeSeconds = await ClipboardVault.instance.copySecret(secret);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label copié • Purge automatique dans ${purgeSeconds}s',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openEditor({VaultItem? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OledTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _CredentialEditorSheet(existing: existing),
    );
    if (saved == true && mounted) {
      await _loadItems();
    }
  }

  Future<void> _openDetail(VaultItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: OledTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _CredentialDetailSheet(
        item: item,
        onCopy: _copyWithAutoPurge,
        onEdit: () {
          Navigator.of(sheetCtx).pop();
          unawaited(_openEditor(existing: item));
        },
        onDelete: () async {
          final confirmed = await showDefensiveDeleteDialog(
            sheetCtx,
            title: 'Supprimer ce secret ?',
            itemLabel: item.title,
          );
          if (!confirmed) return;
          await VaultRepository.instance.deleteItem(item.id);
          if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
          if (mounted) await _loadItems();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    final categories = <String>['Toutes', ...VaultItem.categories];

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Rechercher un secret, login, serveur...',
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
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = categories[index];
                final selected = cat == _selectedCategory;
                return ChoiceChip(
                  label: Text(cat, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  selectedColor:
                      OledTheme.accentEmerald.withValues(alpha: 0.22),
                  backgroundColor: OledTheme.surfaceCard,
                  side: BorderSide(
                    color: selected
                        ? OledTheme.accentEmerald
                        : OledTheme.borderSubtle,
                  ),
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedCategory = cat);
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
                : items.isEmpty
                    ? Center(
                        child: Text(
                          _allItems.isEmpty
                              ? 'Aucun secret enregistré.\nAppuyez sur + pour sceller votre premier identifiant.'
                              : 'Aucun résultat pour cette recherche.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: OledTheme.textSecondary,
                            fontSize: 13.5,
                          ),
                        ),
                      )
                    : ListView.builder(
                        // Section 6 : dégagement bas 120px anti-recouvrement FAB
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              onTap: () => unawaited(_openDetail(item)),
                              leading: CircleAvatar(
                                backgroundColor: OledTheme.accentEmerald
                                    .withValues(alpha: 0.14),
                                child: const Icon(
                                  Icons.vpn_key_outlined,
                                  size: 20,
                                  color: OledTheme.accentEmerald,
                                ),
                              ),
                              title: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: OledTheme.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                '${item.category}${item.login.isNotEmpty ? ' • ${item.login}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: OledTheme.textSecondary,
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: 'Copier le mot de passe',
                                icon: const Icon(
                                  Icons.copy_rounded,
                                  size: 19,
                                  color: OledTheme.accentBlue,
                                ),
                                onPressed: () => unawaited(
                                  _copyWithAutoPurge(
                                    'Mot de passe',
                                    item.password,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null, // Règle #6 obligatoire
        backgroundColor: OledTheme.accentEmerald,
        foregroundColor: OledTheme.bgPrimary,
        onPressed: () => unawaited(_openEditor()),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CredentialDetailSheet extends StatefulWidget {
  const _CredentialDetailSheet({
    required this.item,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  final VaultItem item;
  final Future<void> Function(String label, String value) onCopy;
  final VoidCallback onEdit;
  final Future<void> Function() onDelete;

  @override
  State<_CredentialDetailSheet> createState() => _CredentialDetailSheetState();
}

class _CredentialDetailSheetState extends State<_CredentialDetailSheet> {
  bool _showPassword = false;
  bool _showPin = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: OledTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.category,
                          style: const TextStyle(
                            fontSize: 12,
                            color: OledTheme.accentEmerald,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Modifier',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: widget.onEdit,
                  ),
                  IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(
                      Icons.delete_outline,
                      color: OledTheme.accentRed,
                    ),
                    onPressed: () => unawaited(widget.onDelete()),
                  ),
                ],
              ),
              const Divider(height: 24),
              if (item.login.isNotEmpty)
                _SecretRow(
                  label: 'Identifiant / Login',
                  value: item.login,
                  obscured: false,
                  onCopy: () => unawaited(widget.onCopy('Login', item.login)),
                ),
              if (item.password.isNotEmpty)
                _SecretRow(
                  label: 'Mot de passe / Clé',
                  value: item.password,
                  obscured: !_showPassword,
                  onToggleVisibility: () =>
                      setState(() => _showPassword = !_showPassword),
                  onCopy: () =>
                      unawaited(widget.onCopy('Mot de passe', item.password)),
                ),
              if (item.secondaryPin.isNotEmpty)
                _SecretRow(
                  label: 'Code PIN secondaire',
                  value: item.secondaryPin,
                  obscured: !_showPin,
                  onToggleVisibility: () =>
                      setState(() => _showPin = !_showPin),
                  onCopy: () =>
                      unawaited(widget.onCopy('Code PIN', item.secondaryPin)),
                ),
              if (item.url.isNotEmpty)
                _SecretRow(
                  label: 'URL / Service / Hôte',
                  value: item.url,
                  obscured: false,
                  onCopy: () => unawaited(widget.onCopy('URL', item.url)),
                ),
              if (item.notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Notes stratégiques',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: OledTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: OledTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: OledTheme.borderSubtle),
                  ),
                  child: Text(
                    item.notes,
                    style: const TextStyle(
                      color: OledTheme.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SecretRow extends StatelessWidget {
  const _SecretRow({
    required this.label,
    required this.value,
    required this.obscured,
    required this.onCopy,
    this.onToggleVisibility,
  });

  final String label;
  final String value;
  final bool obscured;
  final VoidCallback onCopy;
  final VoidCallback? onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: OledTheme.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: OledTheme.borderSubtle),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: OledTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    obscured ? '••••••••••••' : value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                      color: OledTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (onToggleVisibility != null)
              IconButton(
                icon: Icon(
                  obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                  color: OledTheme.textSecondary,
                ),
                onPressed: onToggleVisibility,
              ),
            IconButton(
              icon: const Icon(
                Icons.copy_rounded,
                size: 19,
                color: OledTheme.accentEmerald,
              ),
              onPressed: onCopy,
            ),
          ],
        ),
      ),
    );
  }
}

class _CredentialEditorSheet extends StatefulWidget {
  const _CredentialEditorSheet({this.existing});
  final VaultItem? existing;

  @override
  State<_CredentialEditorSheet> createState() => _CredentialEditorSheetState();
}

class _CredentialEditorSheetState extends State<_CredentialEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _loginCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _notesCtrl;

  late String _category;
  bool _obscurePassword = true;
  bool _showGenerator = false;
  double _genLength = 20;
  bool _genUpper = true;
  bool _genLower = true;
  bool _genDigits = true;
  bool _genSymbols = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _loginCtrl = TextEditingController(text: e?.login ?? '');
    _passwordCtrl = TextEditingController(text: e?.password ?? '');
    _pinCtrl = TextEditingController(text: e?.secondaryPin ?? '');
    _urlCtrl = TextEditingController(text: e?.url ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _category = e?.category ?? VaultItem.categories.first;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    _pinCtrl.dispose();
    _urlCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _generatePassword() {
    if (!_genUpper && !_genLower && !_genDigits && !_genSymbols) {
      setState(() => _genLower = true);
    }
    final generated = PasswordGenerator.generate(
      length: _genLength.round(),
      includeUppercase: _genUpper,
      includeLowercase: _genLower,
      includeDigits: _genDigits,
      includeSymbols: _genSymbols,
    );
    HapticFeedback.lightImpact();
    setState(() {
      _passwordCtrl.text = generated;
      _obscurePassword = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    setState(() => _isSaving = true);

    final item = VaultItem(
      id: widget.existing?.id ?? const Uuid().v4(),
      category: _category,
      title: _titleCtrl.text.trim(),
      login: _loginCtrl.text.trim(),
      password: _passwordCtrl.text,
      secondaryPin: _pinCtrl.text.trim(),
      url: _urlCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    await VaultRepository.instance.upsertItem(item);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final strength = PasswordGenerator.evaluateStrength(_passwordCtrl.text);
    final entropy = PasswordGenerator.calculateEntropyBits(_passwordCtrl.text);
    final strengthColor = switch (strength) {
      PasswordStrength.weak => OledTheme.accentRed,
      PasswordStrength.medium => OledTheme.accentAmber,
      PasswordStrength.armored => OledTheme.accentEmerald,
    };

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
                    ? 'Nouvel Identifiant / Secret'
                    : 'Modifier le Secret',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: OledTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Titre *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Titre requis' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true, // Règle #6 obligatoire
                decoration: const InputDecoration(labelText: 'Catégorie'),
                dropdownColor: OledTheme.surfaceCard,
                items: VaultItem.categories
                    .map(
                      (c) => DropdownMenuItem<String>(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _loginCtrl,
                decoration:
                    const InputDecoration(labelText: 'Identifiant / Login'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Mot de passe / Clé SSH / API',
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Générateur cryptographique',
                        icon: Icon(
                          Icons.auto_fix_high_rounded,
                          color: _showGenerator
                              ? OledTheme.accentEmerald
                              : OledTheme.accentBlue,
                        ),
                        onPressed: () =>
                            setState(() => _showGenerator = !_showGenerator),
                      ),
                      IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_passwordCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (entropy / 100).clamp(0.08, 1.0),
                          minHeight: 6,
                          backgroundColor: OledTheme.surfaceCard,
                          color: strengthColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${PasswordGenerator.strengthLabel(strength)} (${entropy.round()} bits)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: strengthColor,
                      ),
                    ),
                  ],
                ),
              ],
              if (_showGenerator) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: OledTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: OledTheme.accentEmerald.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Générateur Random.secure()',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: OledTheme.accentEmerald,
                            ),
                          ),
                          Text(
                            '${_genLength.round()} car.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: OledTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _genLength,
                        min: 8,
                        max: 48,
                        divisions: 40,
                        activeColor: OledTheme.accentEmerald,
                        onChanged: (v) => setState(() => _genLength = v),
                      ),
                      Wrap(
                        spacing: 6,
                        children: [
                          FilterChip(
                            label: const Text('A-Z'),
                            selected: _genUpper,
                            onSelected: (v) => setState(() => _genUpper = v),
                          ),
                          FilterChip(
                            label: const Text('a-z'),
                            selected: _genLower,
                            onSelected: (v) => setState(() => _genLower = v),
                          ),
                          FilterChip(
                            label: const Text('0-9'),
                            selected: _genDigits,
                            onSelected: (v) => setState(() => _genDigits = v),
                          ),
                          FilterChip(
                            label: const Text('!@#'),
                            selected: _genSymbols,
                            onSelected: (v) => setState(() => _genSymbols = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _generatePassword,
                        icon: const Icon(Icons.bolt_rounded, size: 18),
                        label: const Text('Forger un secret blindé'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _pinCtrl,
                decoration:
                    const InputDecoration(labelText: 'Code PIN secondaire'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _urlCtrl,
                decoration:
                    const InputDecoration(labelText: 'URL / Service / IP'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Notes stratégiques'),
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
                  _isSaving ? 'Scellement...' : 'Enregistrer dans le coffre',
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