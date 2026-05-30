import 'package:flutter_test/flutter_test.dart';
import 'package:xlights_layout/main.dart';

void main() {
  testWidgets('shows empty state on launch', (tester) async {
    await tester.pumpWidget(const XLightsLayoutApp());
    expect(find.text('Load your xLights layout'), findsOneWidget);
    expect(find.text('Load files'), findsWidgets);
  });
}
