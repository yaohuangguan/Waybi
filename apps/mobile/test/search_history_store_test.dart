import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waybi_mobile/data/search_history_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recent searches keep newest unique queries and cap the list', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SearchHistoryStore();
    for (final query in [
      'Auckland Airport',
      '42 veri',
      'Queen Street',
      'Tokyo Station',
      'Sydney Opera House',
      '221B Baker Street',
      'Eiffel Tower',
    ]) {
      await store.remember(query);
    }
    await store.remember('42 VERI');
    final history = await store.load();
    expect(history, hasLength(SearchHistoryStore.maxItems));
    expect(history.first, '42 VERI');
    expect(
      history.where((item) => item.toLowerCase() == '42 veri'),
      hasLength(1),
    );
    expect(history, isNot(contains('Auckland Airport')));
  });

  test('recent search can be removed', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SearchHistoryStore();
    await store.remember('42 Verissimo Drive');
    await store.remove('42 verissimo drive');
    expect(await store.load(), isEmpty);
  });
}
