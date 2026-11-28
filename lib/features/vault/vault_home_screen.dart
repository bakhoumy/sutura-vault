import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';
import 'package:sutura_vault/features/security_center/security_center_screen.dart';
import 'package:sutura_vault/features/vault/tabs/black_audio_tab.dart';
import 'package:sutura_vault/features/vault/tabs/black_notes_tab.dart';
import 'package:sutura_vault/features/vault/tabs/credentials_tab.dart';
import 'package:sutura_vault/features/vault/tabs/documents_tab.dart';

/// Tableau de bord principal hébergeant les 4 compartiments de l'IT-Vault.
class VaultHomeScreen extends StatefulWidget {
  const VaultHomeScreen({
    required this.onLockRequested,
    required this.onVaultWiped,
    super.key,
  });

  final VoidCallback onLockRequested;
  final VoidCallback onVaultWiped;

  @override
  State<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends State<VaultHomeScreen> {
  int _selectedIndex = 0;

  static const List<String> _titles = <String>[
    'Identifiants & Clés IT',
    'Porte-Documents',
    'Notes Noires',
    'Mémos Vocaux Noirs',
  ];

  static const List<Widget> _tabs = <Widget>[
    CredentialsTab(),
    DocumentsTab(),
    BlackNotesTab(),
    BlackAudioTab(),
  ];

  void _openSecurityCenter() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SecurityCenterScreen(
          onLockRequested: widget.onLockRequested,
          onVaultWiped: widget.onVaultWiped,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[_selectedIndex],
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Centre de Sécurité, Audit & Sauvegarde',
            icon: const Icon(
              Icons.shield_outlined,
              color: OledTheme.accentBlue,
            ),
            onPressed: _openSecurityCenter,
          ),
          IconButton(
            tooltip: 'Verrouiller le coffre',
            icon: const Icon(
              Icons.lock_outline,
              color: OledTheme.accentEmerald,
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.onLockRequested();
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: OledTheme.surfaceDark,
        indicatorColor: OledTheme.accentEmerald.withValues(alpha: 0.18),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          HapticFeedback.selectionClick();
          setState(() => _selectedIndex = index);
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.key_outlined),
            selectedIcon: Icon(Icons.key, color: OledTheme.accentEmerald),
            label: 'Secrets',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge, color: OledTheme.accentEmerald),
            label: 'Docs',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon:
                Icon(Icons.description, color: OledTheme.accentEmerald),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none_outlined),
            selectedIcon: Icon(Icons.mic, color: OledTheme.accentEmerald),
            label: 'Audio',
          ),
        ],
      ),
    );
  }
}