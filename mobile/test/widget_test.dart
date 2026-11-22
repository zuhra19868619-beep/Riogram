import 'package:flutter_test/flutter_test.dart';
import 'package:riogram/main.dart';

void main() {
  testWidgets('Riogram renders navigation', (tester) async {
    await tester.pumpWidget(const RiogramApp());
    expect(find.text('Чаты'), findsWidgets);
    expect(find.text('Контакты'), findsOneWidget);
  });
}
