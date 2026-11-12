import 'package:flutter_test/flutter_test.dart';
import 'package:vzhuh/main.dart';

void main() {
  testWidgets('shows the waiting and connect options', (tester) async {
    await tester.pumpWidget(const VzhuhApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Вжух'), findsOneWidget);
    expect(find.text('Ожидать подключения'), findsOneWidget);
    expect(find.text('Подключить второй экземпляр'), findsOneWidget);
    expect(
      find.text(
        'Демо только на этом ПК (127.0.0.1). Соединение не шифруется '
        'и не проверяет личность. Экран и ввод не передаются.',
      ),
      findsOneWidget,
    );
  });
}
