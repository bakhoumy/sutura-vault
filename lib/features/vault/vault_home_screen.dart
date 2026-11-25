import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';

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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 46,
                color: OledTheme.accentEmerald,
              ),
              const SizedBox(height: 16),
              Text(
                _titles[_selectedIndex],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: OledTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Base SQLCipher AES-256 ouverte et isolée.\nLes 4 compartiments complets arrivent au Jalon 4.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: OledTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
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