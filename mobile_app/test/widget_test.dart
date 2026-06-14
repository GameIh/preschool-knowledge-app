import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preschool_knowledge_app/main.dart';

void main() {
  testWidgets('shows login screen', (tester) async {
    await tester.pumpWidget(const PreschoolKnowledgeApp());

    expect(find.text('База знаний дошкольника'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
    expect(find.text('Регистрация'), findsOneWidget);
    expect(find.text('Пропустить'), findsNothing);
    expect(find.text('Адрес сервера'), findsNothing);
    expect(find.textContaining('offline'), findsNothing);
    expect(find.textContaining('Приложение •'), findsNothing);

    await tester.ensureVisible(find.text('Регистрация'));
    await tester.tap(find.text('Регистрация'));
    await tester.pump();

    expect(find.text('Создать аккаунт'), findsOneWidget);
    expect(find.text('Имя'), findsOneWidget);
  });

  testWidgets('page shell fills the available height', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PageShell(
            title: 'Короткая страница',
            subtitle: 'Проверка фона',
            children: [Text('Контент')],
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(GradientBackground)).height,
      tester.getSize(find.byType(Scaffold)).height,
    );
  });
}
