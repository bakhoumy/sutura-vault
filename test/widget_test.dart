import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sutura_vault/core/theme/oled_theme.dart';
import 'package:sutura_vault/features/auth/pin_input_pad.dart';

void main() {
  testWidgets('PinInputPad Scramble Pad affiche 0-9 et renvoie un PIN 6 chiffres',
      (tester) async {
    String? capturedPin;

    await tester.pumpWidget(
      MaterialApp(
        theme: OledTheme.darkTheme,
        home: Scaffold(
          body: Center(
            child: PinInputPad(
              scramble: true,
              onCompleted: (pin) => capturedPin = pin,
            ),
          ),
        ),
      ),
    );

    for (var d = 0; d <= 9; d++) {
      expect(find.text('$d'), findsOneWidget);
    }

    for (final digit in const <String>['4', '8', '2', '9', '1', '0']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }

    expect(capturedPin, equals('482910'));
  });
}