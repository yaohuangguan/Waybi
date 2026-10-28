import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/domain/map_provider.dart';
import 'package:waybi_mobile/widgets/trips_page.dart';

TripsSnapshot snapshot(String name) => TripsSnapshot(
  quickPlaces: {
    'Home': TripDestination(
      name: name,
      location: const GeoPoint(-36.85, 174.77),
    ),
  },
  quickRoutes: const {},
  recent: [
    TripDestination(name: name, location: const GeoPoint(-36.85, 174.77)),
  ],
  history: const [],
);

void main() {
  test('cached trips publish before any network work, then fast sections publish independently', () async {
    var current = snapshot('Cached Home');
    final slow = Completer<void>();
    final fast = Completer<void>();
    var networkStarted = false;
    final stream = StreamIterator(
      loadTripsInStages(
        readSnapshot: () async => current,
        refreshers: [
          (_) async {
            networkStarted = true;
            await slow.future;
            current = snapshot('Slow account');
          },
          (_) async {
            await fast.future;
            current = snapshot('Fast commute');
          },
        ],
      ),
    );
    expect(await stream.moveNext(), isTrue);
    expect(stream.current.quickPlaces['Home']!.name, 'Cached Home');
    expect(networkStarted, isFalse);
    final next = stream.moveNext();
    fast.complete();
    expect(await next, isTrue);
    expect(stream.current.quickPlaces['Home']!.name, 'Fast commute');
    expect(slow.isCompleted, isFalse);
    slow.complete();
    expect(await stream.moveNext(), isTrue);
    expect(stream.current.quickPlaces['Home']!.name, 'Slow account');
    expect(await stream.moveNext(), isFalse);
  });

  test('an offline enhancement does not discard usable records or stop other sections', () async {
    var current = snapshot('Local records');
    final events = await loadTripsInStages(
      readSnapshot: () async => current,
      refreshers: [
        (_) async => throw StateError('Offline'),
        (publish) async {
          current = snapshot('Updated records');
          publish();
        },
      ],
    ).toList();
    expect(events.first.quickPlaces['Home']!.name, 'Local records');
    expect(events.last.quickPlaces['Home']!.name, 'Updated records');
    expect(events.length, greaterThanOrEqualTo(3));
    expect(
      await loadTripsInStages(
        readSnapshot: () async => current,
        refreshers: const [],
      ).length,
      1,
    );
  });

  test('cancelling a screen does not wait for a stalled provider or publish late results', () async {
    final pending = Completer<void>();
    final received = <TripsSnapshot>[];
    final initial = Completer<void>();
    final sub =
        loadTripsInStages(
          readSnapshot: () async => snapshot('Cached'),
          refreshers: [
            (publish) async {
              await pending.future;
              publish();
            },
          ],
        ).listen((value) {
          received.add(value);
          if (!initial.isCompleted) initial.complete();
        });
    await initial.future;
    await Future<void>.delayed(Duration.zero);
    await sub.cancel().timeout(const Duration(seconds: 1));
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
  });

  testWidgets('Trips keeps cached shortcuts usable while later sections load', (
    t,
  ) async {
    t.view.physicalSize = const Size(500, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final updates = StreamController<TripsSnapshot>();
    await t.pumpWidget(
      MaterialApp(
        home: TripsPage(
          language: 'en',
          loader: () async => snapshot('Unused'),
          progressiveLoader: () => updates.stream,
        ),
      ),
    );
    await t.pump();
    await t.pump();
    updates.add(snapshot('Cached Home'));
    await t.pump();
    expect(find.text('Cached Home'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    updates.add(snapshot('Fresh Home'));
    await t.pump();
    expect(find.text('Fresh Home'), findsOneWidget);
    expect(find.text('Cached Home'), findsNothing);
    unawaited(updates.close());
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'refresh replaces an old stream and errors preserve prior records',
    (t) async {
      final streams = [
        StreamController<TripsSnapshot>(),
        StreamController<TripsSnapshot>(),
      ];
      t.view.physicalSize = const Size(500, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var count = 0;
      await t.pumpWidget(
        MaterialApp(
          home: TripsPage(
            language: 'en',
            loader: () async => snapshot('Unused'),
            progressiveLoader: () => streams[count++].stream,
          ),
        ),
      );
      await t.pump();
      streams[0].add(snapshot('Saved Home'));
      await t.pump();
      final firstRefresh = t
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await t.pump();
      await t.pump();
      expect(count, 2);
      streams[0].add(snapshot('Obsolete Home'));
      streams[1].addError(StateError('Offline'));
      await t.pump();
      expect(find.text('Saved Home'), findsOneWidget);
      expect(find.text('Obsolete Home'), findsNothing);
      expect(find.text('Could not refresh trips right now.'), findsOneWidget);
      streams[1].add(snapshot('Recovered Home'));
      await t.pump();
      expect(find.text('Recovered Home'), findsOneWidget);
      unawaited(streams[1].close());
      await t.pump();
      await firstRefresh;
      await t.pumpWidget(const SizedBox());
      unawaited(streams[0].close());
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'leaving Trips cancels its subscription while a section is still loading',
    (t) async {
      final updates = StreamController<TripsSnapshot>();
      var cancelled = false;
      updates.onCancel = () {
        cancelled = true;
      };
      await t.pumpWidget(
        MaterialApp(
          home: TripsPage(
            language: 'zh',
            loader: () async => snapshot('Unused'),
            progressiveLoader: () => updates.stream,
          ),
        ),
      );
      await t.pump();
      updates.add(snapshot('Home'));
      await t.pump();
      await t.pumpWidget(const SizedBox());
      await t.pump();
      expect(cancelled, isTrue);
      updates.add(snapshot('Late'));
      unawaited(updates.close());
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
}
