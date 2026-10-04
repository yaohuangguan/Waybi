import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/data/account_repository.dart';

void main() {
  test('account profile parses synced Home and Work locations', () {
    final profile = AccountProfile.fromJson({
      'user': {
        'id': 'u1',
        'email': 'sam@example.com',
        'providers': ['google'],
      },
      'subscription': {'plan': 'free'},
      'quickLocations': [
        {
          'label': 'Home',
          'name': 'Home',
          'address': 'Queen Street',
          'latitude': -36.85,
          'longitude': 174.76,
          'provider': 'independent',
        },
        {
          'label': 'Work',
          'name': 'Office',
          'address': 'Albert Street',
          'latitude': -36.84,
          'longitude': 174.77,
          'provider': 'google',
        },
      ],
    });

    expect(profile.quickLocations, hasLength(2));
    expect(profile.quickLocations.first['label'], 'Home');
    expect(profile.quickLocations.last['provider'], 'google');
  });
}
