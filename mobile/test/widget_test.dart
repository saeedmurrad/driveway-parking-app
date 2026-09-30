import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkspace/src/ui.dart';

void main() {
  test('money and date formatting', () {
    expect(money(12.5), '£12.50');
    expect(money('3.1'), '£3.10');
  });

  testWidgets('status chip shows a friendly label', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StatusChip('pending_approval'))));
    expect(find.text('Pending approval'), findsOneWidget);
  });
}
