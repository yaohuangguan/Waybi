import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/discover_page.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';

void main() {
  testWidgets(
    'Discover is driven by journey history and can start a new trip',
    (tester) async {
      final snapshot = TripsSnapshot(
        quickPlaces: const {},
        quickRoutes: const {},
        recent: const [],
        history: [
          TripHistoryItem(
            destination: const TripDestination(
              name: 'Piha',
              location: GeoPoint(-36.954, 174.469),
            ),
            mode: 'drive',
            distanceMeters: 42000,
            durationSeconds: 3600,
            createdAt: DateTime(2026, 8, 1),
          ),
          TripHistoryItem(
            destination: const TripDestination(
              name: 'Mission Bay',
              location: GeoPoint(-36.848, 174.832),
            ),
            mode: 'drive',
            distanceMeters: 9000,
            durationSeconds: 1200,
            createdAt: DateTime(2026, 9, 1),
          ),
        ],
      );

      DiscoverAction? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<DiscoverAction>(
                      MaterialPageRoute(
                        builder: (_) => DiscoverPage(
                          language: 'en',
                          loader: () async => snapshot,
                          origin: const GeoPoint(-36.8485, 174.7633),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('2 journeys · 2 places'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('A different direction'), 200);
      expect(find.text('A different direction'), findsOneWidget);
      expect(
        find.text('North has fewer places you have visited from here.'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Choose somewhere new'));
      await tester.tap(find.text('Choose somewhere new'));
      await tester.pumpAndSettle();
      expect(result, DiscoverAction.newDestination);
    },
  );
}
