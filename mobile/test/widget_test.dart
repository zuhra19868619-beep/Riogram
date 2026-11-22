import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riogram/main.dart';

void main() {
  testWidgets('Riogram shows chats and navigation', (tester) async {
    await tester.pumpWidget(const RiogramApp());
    expect(find.text('Riogram'), findsOneWidget);
    expect(find.text('Чаты'), findsWidgets);
    expect(find.text('Контакты'), findsOneWidget);
    expect(find.text('Звонки'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);
  });

  testWidgets('Contact tab shows synchronization action', (tester) async {
    await tester.pumpWidget(const RiogramApp());
    await tester.tap(find.text('Контакты'));
    await tester.pump();
    expect(find.text('Синхронизировать контакты'), findsOneWidget);
  });

  testWidgets('Chat opens a demo conversation', (tester) async {
    await tester.pumpWidget(const RiogramApp());
    await tester.tap(find.text('Александр'));
    await tester.pumpAndSettle();
    expect(find.text('Демо: сообщения не отправляются на сервер'), findsOneWidget);
    expect(find.byIcon(Icons.send), findsOneWidget);
  });
}
