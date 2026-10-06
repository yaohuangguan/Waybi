import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:geolocator/geolocator.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/domain/route_option.dart';
import 'package:waybi_mobile/drive/drive_engine.dart';
import 'package:waybi_mobile/drive/voice_engine.dart';
import 'package:waybi_mobile/providers/independent_navigation_engine.dart';
import 'package:waybi_mobile/providers/independent_routing_provider.dart';

class _SilentVoice extends VoiceEngine {
  @override
  Future<void> dispose() async {}
}

class _FakeDrive extends DriveEngine {
  _FakeDrive() : super(voiceEngine: _SilentVoice());

  @override
  Future<void> startLocal({Position? initialPosition}) async {
    active = true;
  }

  @override
  Future<void> speakMessage(String message) async {}

  @override
  Future<void> stop() async {
    active = false;
    setRoute(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Independent map accepts all Google-free global address providers and rejects Google', () {
    const policy = ProviderPolicy(MapProvider.independent);
    for (final provider in [
      'osm',
      'geoapify',
      'tomtom',
      'regional:linz-nz-addresses',
      'regional:sample-official',
      'derived:address-interpolation',
    ]) {
      expect(
        policy.canDisplay(ProviderReference(provider, 'result-1')),
        isTrue,
        reason: '$provider must be selectable on Waybi Independent map',
      );
    }
    expect(
      policy.canDisplay(const ProviderReference('google', 'google-place-id')),
      isFalse,
      reason: 'Independent map must never depend on Google Places results',
    );
  });

  test('Google-free address can be selected, routed and started in Independent navigation', () async {
    const candidate = PlaceCandidate(
      name: '42 Verissimo Drive',
      address: '42 Verissimo Drive, Māngere, Auckland 2022, New Zealand',
      kind: PlaceKind.address,
      location: GeoPoint(-36.989, 174.789),
      reference: ProviderReference('tomtom', 'tt-42-verissimo'),
    );
    const policy = ProviderPolicy(MapProvider.independent);
    expect(policy.canDisplay(candidate.reference), isTrue);

    final destination = candidate.toPlace(candidate.location!);
    expect(destination.name, '42 Verissimo Drive');
    expect(destination.location, const GeoPoint(-36.989, 174.789));

    final requestedHosts = <String>[];
    final routing = IndependentRoutingProvider(
      client: MockClient((request) async {
        requestedHosts.add(request.url.host);
        return http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'distance': 18000,
                'duration': 1200,
                'geometry': {
                  'coordinates': [
                    [174.7633, -36.8485],
                    [174.789, -36.989],
                  ],
                },
                'legs': [
                  {
                    'steps': [
                      {
                        'distance': 18000,
                        'duration': 1200,
                        'name': 'State Highway 20',
                        'maneuver': {
                          'type': 'depart',
                          'instruction': 'Head south',
                          'location': [174.7633, -36.8485],
                        },
                      },
                    ],
                  },
                ],
              },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(routing.dispose);

    final plan = await routing.route(
      origin: const GeoPoint(-36.8485, 174.7633),
      destination: destination.location,
      language: 'en',
      mode: WaybiTravelMode.drive,
    );
    final route = plan.options.single;
    expect(plan.provider, 'independent');
    expect(route.provider, 'independent');
    expect(route.points.last, destination.location);
    expect(requestedHosts, isNotEmpty);
    expect(requestedHosts.any((host) => host.contains('google')), isFalse);

    final drive = _FakeDrive();
    final navigation = IndependentNavigationEngine(drive);
    addTearDown(() {
      navigation.dispose();
      drive.dispose();
    });
    await navigation.start(route);
    expect(navigation.active, isTrue);
    expect(navigation.route, same(route));
    expect(drive.active, isTrue);
  });
}
