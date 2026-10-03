import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:waybi_mobile/data/traffic_flow_repository.dart';
import 'package:waybi_mobile/domain/traffic_flow.dart';

void main() {
  test(
    'traffic flow repository parses live motorway congestion segments',
    () async {
      final repository = TrafficFlowRepository(
        baseUrl: 'https://example.test',
        client: MockClient((request) async {
          expect(request.url.path, '/api/traffic-flow');
          return http.Response(
            jsonEncode({
              'syncStatus': 'live',
              'sourceUpdatedAt': '2026-10-03T09:24:28.587+13:00',
              'checkedAt': '2026-10-03T09:25:00+13:00',
              'segments': [
                {
                  'id': 'nzta:traffic:2',
                  'motorway': 'Northern Motorway',
                  'name': 'Oteha Valley Rd - Upper Harb Hwy',
                  'direction': 'Southbound',
                  'congestion': 'Free Flow',
                  'level': 'free',
                  'start': {'latitude': -36.7183, 'longitude': 174.7126},
                  'end': {'latitude': -36.7506, 'longitude': 174.7260},
                },
              ],
            }),
            200,
          );
        }),
      );

      final snapshot = await repository.load();
      expect(snapshot.syncStatus, 'live');
      expect(snapshot.segments, hasLength(1));
      expect(snapshot.segments.single.level, TrafficFlowLevel.free);
      expect(snapshot.segments.single.motorway, 'Northern Motorway');
      repository.dispose();
    },
  );
}
