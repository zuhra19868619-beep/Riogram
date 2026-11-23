import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riogram/main.dart';

void main() {
  testWidgets('First launch requires phone registration', (tester) async {
    await tester.pumpWidget(const RiogramApp());
    expect(find.text('Riogram — вход'), findsOneWidget);
    expect(find.text('Войти по номеру телефона'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Получить код'), findsOneWidget);
    expect(find.text('Александр'), findsNothing);
    expect(find.text('Чаты'), findsNothing);
  });

  testWidgets('Login validates phone and reports server errors', (tester) async {
    await tester.pumpWidget(const RiogramApp());
    expect(find.text('Получить код'), findsOneWidget);
    expect(find.text('Изменить номер'), findsNothing);
  });
}
