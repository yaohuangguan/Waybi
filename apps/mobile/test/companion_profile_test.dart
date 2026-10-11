import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/data/account_repository.dart';

void main() {
  test('old profile without permanent stats stays compatible', () {
    final oldProfile = AccountProfile.fromJson({
      'user': {'id': 'u-1', 'email': 'test@example.com'},
      'routeHistory': [
        {'id': 'old', 'distanceMeters': 1200, 'durationSeconds': 300},
      ],
    });
    expect(oldProfile.companionTotals, isNull);
    expect(oldProfile.routes.length, 1);
  });

  test('new profile reads durable counters independent of recent routes', () {
    final profile = AccountProfile.fromJson({
      'user': {'id': 'u-1', 'email': 'test@example.com'},
      'routeHistory': [],
      'companionTotals': {
        'distanceMeters': 2543000,
        'tripCount': 260,
        'durationSeconds': 720000,
      },
    });
    expect(profile.companionTotals?.distanceMeters, 2543000);
    expect(profile.companionTotals?.tripCount, 260);
    expect(profile.companionTotals?.durationSeconds, 720000);
  });
}
