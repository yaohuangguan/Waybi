import 'package:flutter_test/flutter_test.dart';

/// Presses and holds [finder] long enough to complete a hold-to-end button.
Future<void> holdToEnd(
  WidgetTester tester,
  Finder finder, {
  Duration hold = const Duration(milliseconds: 1200),
}) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  const step = Duration(milliseconds: 50);
  for (var elapsed = Duration.zero; elapsed < hold; elapsed += step) {
    await tester.pump(step);
  }
  await gesture.up();
  await tester.pump();
}
