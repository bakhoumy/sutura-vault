import 'package:flutter_test/flutter_test.dart';
import 'package:sutura_vault/main.dart';

void main() {
  testWidgets('SuturaVaultApp démarre proprement en thème OLED', (tester) async {
    await tester.pumpWidget(const SuturaVaultApp());
    expect(find.text('SUTURA VAULT'), findsOneWidget);
  });
}