import 'package:flutter_test/flutter_test.dart';
import 'package:vzhuh/main.dart';

void main() {
  testWidgets('shows the waiting and connect options', (tester) async {
    await tester.pumpWidget(const VzhuhApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Вжух'), findsOneWidget);
    expect(find.text('Ожидать подключения'), findsOneWidget);
    expect(find.text('Подключиться к ПК'), findsOneWidget);
    expect(
      find.text(
        'Предварительная версия: соединение не шифруется и '
        'не использует аутентификацию. Только тестовая локальная сеть.',
      ),
      findsOneWidget,
    );
  });
}
