import 'package:flutter_test/flutter_test.dart';
import 'package:parkspace/main.dart';

void main() {
  testWidgets('app boots to search screen', (tester) async {
    await tester.pumpWidget(const ParkSpaceApp());
    expect(find.text('ParkSpace — find a driveway'), findsOneWidget);
  });
}
