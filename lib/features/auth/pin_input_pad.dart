import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';

/// Pavé numérique interne souverain (SEC-04).
///
/// Utilise exclusivement des boutons internes (bannit Gboard / keyloggers) et
/// mélange les chiffres 0-9 via [Random.secure] quand [scramble] est actif.
class PinInputPad extends StatefulWidget {
  const PinInputPad({
    required this.onCompleted,
    super.key,
    this.pinLength = 6,
    this.scramble = true,
    this.enabled = true,
    this.showBiometricButton = false,
    this.onBiometricPressed,
    this.errorText,
  });

  final ValueChanged<String> onCompleted;
  final int pinLength;
  final bool scramble;
  final bool enabled;
  final bool showBiometricButton;
  final VoidCallback? onBiometricPressed;
  final String? errorText;

  @override
  State<PinInputPad> createState() => _PinInputPadState();
}

class _PinInputPadState extends State<PinInputPad> {
  String _pin = '';
  late List<int> _digits;

  @override
  void initState() {
    super.initState();
    _digits = _buildDigits(widget.scramble);
  }

  @override
  void didUpdateWidget(covariant PinInputPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scramble != widget.scramble) {
      _digits = _buildDigits(widget.scramble);
    }
  }

  List<int> _buildDigits(bool scramble) {
    final list = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 0];
    if (scramble) {
      final rng = Random.secure();
      for (var i = list.length - 1; i > 0; i--) {
        final j = rng.nextInt(i + 1);
        final tmp = list[i];
        list[i] = list[j];
        list[j] = tmp;
      }
    }
    return list;
  }

  void _onDigitTap(int digit) {
    if (!widget.enabled || _pin.length >= widget.pinLength) return;
    HapticFeedback.lightImpact();

    final nextPin = '$_pin$digit';
    setState(() => _pin = nextPin);

    if (nextPin.length == widget.pinLength) {
      widget.onCompleted(nextPin);
    }
  }

  void _onBackspace() {
    if (!widget.enabled || _pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _onClear() {
    if (!widget.enabled || _pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin = '';
      if (widget.scramble) {
        _digits = _buildDigits(true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Indicateur 6 points PIN
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(widget.pinLength, (index) {
            final filled = index < _pin.length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: filled ? 15 : 13,
              height: filled ? 15 : 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled
                    ? OledTheme.accentEmerald
                    : OledTheme.surfaceCard,
                border: Border.all(
                  color: widget.errorText != null
                      ? OledTheme.accentRed
                      : (filled
                          ? OledTheme.accentEmerald
                          : OledTheme.borderSubtle),
                  width: 1.5,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 22,
          child: widget.errorText != null
              ? Text(
                  widget.errorText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: OledTheme.accentRed,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 14),

        // Grille 4x3 souveraine
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            children: [
              _buildRow(<int>[_digits[0], _digits[1], _digits[2]]),
              const SizedBox(height: 12),
              _buildRow(<int>[_digits[3], _digits[4], _digits[5]]),
              const SizedBox(height: 12),
              _buildRow(<int>[_digits[6], _digits[7], _digits[8]]),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildLeftActionKey(),
                  _buildDigitKey(_digits[9]),
                  _buildActionKey(
                    icon: Icons.backspace_outlined,
                    tooltip: 'Effacer',
                    onTap: _onBackspace,
                    onLongPress: _onClear,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(List<int> values) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: values.map(_buildDigitKey).toList(),
    );
  }

  Widget _buildDigitKey(int digit) {
    return SizedBox(
      width: 74,
      height: 62,
      child: Material(
        color: OledTheme.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: OledTheme.borderSubtle),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.enabled ? () => _onDigitTap(digit) : null,
          child: Center(
            child: Text(
              digit.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: widget.enabled
                    ? OledTheme.textPrimary
                    : OledTheme.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeftActionKey() {
    if (widget.showBiometricButton && widget.onBiometricPressed != null) {
      return _buildActionKey(
        icon: Icons.fingerprint,
        iconColor: OledTheme.accentEmerald,
        tooltip: 'Biométrie',
        onTap: widget.onBiometricPressed!,
      );
    }
    return _buildActionKey(
      icon: Icons.clear_all_rounded,
      tooltip: 'Réinitialiser',
      onTap: _onClear,
    );
  }

  Widget _buildActionKey({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    Color? iconColor,
  }) {
    return SizedBox(
      width: 74,
      height: 62,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: OledTheme.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: OledTheme.borderSubtle),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.enabled ? onTap : null,
            onLongPress: widget.enabled ? onLongPress : null,
            child: Center(
              child: Icon(
                icon,
                size: 24,
                color: widget.enabled
                    ? (iconColor ?? OledTheme.textSecondary)
                    : OledTheme.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}