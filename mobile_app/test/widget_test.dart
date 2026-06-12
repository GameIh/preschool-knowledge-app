import 'package:flutter_test/flutter_test.dart';
import 'package:preschool_knowledge_app/main.dart';

void main() {
  testWidgets('shows login screen', (tester) async {
    await tester.pumpWidget(const PreschoolKnowledgeApp());

    expect(find.text('База знаний дошкольника'), findsOneWidget);
    expect(find.text('Войти'), findsOneWidget);
    expect(find.text('Пропустить'), findsOneWidget);
  });
}
