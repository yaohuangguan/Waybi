import 'package:flutter_test/flutter_test.dart';
import 'package:waybi_mobile/app/request_generation.dart';
import 'package:waybi_mobile/app/trip_state.dart';
import 'package:waybi_mobile/domain/map_provider.dart' show JourneyPhase;

TripState run(TripState start, List<TripEvent> events) =>
    events.fold(start, transition);

void main() {
  group('transition', () {
    test('a normal drive: place, preview, start, guidance, arrival, end', () {
      var state = run(const TripIdle(), const [PlaceChosen()]);
      expect(state, const TripPlaceSelected());
      expect(state.journeyPhase, JourneyPhase.placeSelected);
      state = transition(state, const PreviewRequested());
      expect(state, const TripPlaceSelected(routing: true));
      expect(state.previewLoading, isTrue);
      state = transition(state, const PreviewSettled(hasPlan: true));
      expect(state, const TripPreviewing());
      expect(state.journeyPhase, JourneyPhase.routePreview);
      state = transition(state, const StartRequested());
      expect(state, const TripStarting());
      expect(state.busy, isTrue);
      state = transition(state, const NavigationStarted());
      expect(state, const TripNavigating());
      expect(state.guidanceRunning, isTrue);
      state = transition(state, const ArrivalChanged(true));
      expect(state, const TripNavigating(arrival: true));
      state = transition(state, const EndRequested());
      expect(state, const TripEnding());
      expect(state.guidanceRunning, isTrue);
      expect(transition(state, const NavigationEnded()), const TripIdle());
      expect(
        transition(state, const NavigationEnded(parkingLeg: true)),
        const TripParkingLeg(),
      );
    });

    test('a failed first preview returns to the place card; a failed '
        'reload keeps the plan', () {
      expect(
        run(const TripPlaceSelected(), const [
          PreviewRequested(),
          PreviewSettled(hasPlan: false),
        ]),
        const TripPlaceSelected(),
      );
      expect(
        run(const TripPreviewing(), const [
          PreviewRequested(),
          PreviewSettled(hasPlan: true),
        ]),
        const TripPreviewing(),
      );
      expect(
        transition(const TripPreviewing(), const PreviewRequested()),
        const TripPreviewing(PreviewActivity.reloading),
      );
    });

    test('transit loading and detours are preview activities', () {
      final transit = transition(
        const TripPreviewing(),
        const TransitLoadStarted(),
      );
      expect(transit, const TripPreviewing(PreviewActivity.loadingTransit));
      expect(transit.previewLoading, isTrue);
      expect(transit.busy, isFalse);
      final detour = transition(const TripPreviewing(), const DetourStarted());
      expect(detour, const TripPreviewing(PreviewActivity.findingDetour));
      expect(detour.busy, isTrue);
      expect(
        transition(detour, const StartRequested()),
        detour,
        reason: 'no start while a detour is being found',
      );
      expect(
        transition(detour, const PreviewSettled(hasPlan: true)),
        const TripPreviewing(),
      );
      expect(
        transition(const TripIdle(), const TransitLoadStarted()),
        const TripIdle(),
      );
      expect(
        transition(const TripIdle(), const DetourStarted()),
        const TripIdle(),
      );
    });

    test('closing or choosing another place cancels a start', () {
      expect(
        transition(const TripStarting(), const PreviewClosed()),
        const TripPlaceSelected(),
      );
      expect(
        transition(const TripStarting(), const PlaceCleared()),
        const TripIdle(),
      );
      expect(
        transition(const TripStarting(), const PlaceChosen()),
        const TripPlaceSelected(),
      );
      // The aborted start then finds nothing to undo.
      expect(
        transition(const TripPlaceSelected(), const StartAborted()),
        const TripPlaceSelected(),
      );
      expect(
        transition(const TripStarting(), const StartAborted()),
        const TripPreviewing(),
      );
      expect(
        transition(
          const TripPlaceSelected(routing: true),
          const PreviewClosed(),
        ),
        const TripPlaceSelected(),
      );
    });

    test('late answers after the user moved on change nothing', () {
      for (final state in const <TripState>[
        TripIdle(),
        TripNavigating(),
        TripTransit(),
        TripJustDrive(),
      ]) {
        expect(
          transition(state, const PreviewSettled(hasPlan: true)),
          state,
          reason: '$state',
        );
        expect(transition(state, const NavigationStarted()), state);
        expect(transition(state, const TransitTripStarted()), state);
      }
      expect(
        transition(const TripIdle(), const ArrivalChanged(true)),
        const TripIdle(),
      );
      expect(
        transition(const TripIdle(), const EndRequested()),
        const TripIdle(),
      );
      expect(
        transition(const TripIdle(), const NavigationEnded()),
        const TripIdle(),
      );
    });

    test('active trips ignore place selection and clearing', () {
      for (final state in const <TripState>[
        TripNavigating(),
        TripEnding(),
        TripTransit(),
        TripJustDrive(starting: true),
      ]) {
        expect(transition(state, const PlaceChosen()), state);
        expect(transition(state, const PlaceCleared()), state);
        expect(transition(state, const PreviewRequested()), state);
        expect(transition(state, const StartRequested()), state);
      }
    });

    test('transit trips and Just Drive', () {
      expect(
        run(const TripStarting(), const [TransitTripStarted()]),
        const TripTransit(),
      );
      expect(
        transition(const TripTransit(), const TransitTripEnded()),
        const TripIdle(),
      );
      expect(
        transition(const TripIdle(), const TransitTripEnded()),
        const TripIdle(),
      );
      for (final from in const <TripState>[
        TripIdle(),
        TripPlaceSelected(),
        TripPreviewing(),
        TripParkingLeg(),
      ]) {
        expect(
          transition(from, const DriveRequested()),
          const TripJustDrive(starting: true),
        );
      }
      for (final from in const <TripState>[
        TripNavigating(),
        TripEnding(),
        TripTransit(),
      ]) {
        expect(transition(from, const DriveRequested()), from);
      }
      final starting = const TripJustDrive(starting: true);
      expect(starting.busy, isTrue);
      expect(transition(starting, const DriveStarted()), const TripJustDrive());
      expect(transition(starting, const DriveEnded()), const TripIdle());
      expect(
        transition(const TripIdle(), const DriveStarted()),
        const TripIdle(),
      );
      expect(
        transition(const TripIdle(), const DriveEnded()),
        const TripIdle(),
      );
    });

    test('the parking leg can be dismissed or continued on foot', () {
      expect(
        transition(const TripParkingLeg(), const ParkingLegDismissed()),
        const TripIdle(),
      );
      expect(
        transition(const TripParkingLeg(), const PlaceChosen()),
        const TripPlaceSelected(),
      );
      expect(
        transition(const TripIdle(), const ParkingLegDismissed()),
        const TripIdle(),
      );
    });
  });

  test('states compare by value and describe themselves', () {
    const states = <TripState>[
      TripIdle(),
      TripPlaceSelected(),
      TripPlaceSelected(routing: true),
      TripPreviewing(),
      TripPreviewing(PreviewActivity.reloading),
      TripStarting(),
      TripNavigating(),
      TripNavigating(arrival: true),
      TripEnding(),
      TripTransit(),
      TripJustDrive(),
      TripJustDrive(starting: true),
      TripParkingLeg(),
    ];
    for (var i = 0; i < states.length; i++) {
      for (var j = 0; j < states.length; j++) {
        expect(states[i] == states[j], i == j, reason: '${states[i]}');
      }
      expect(states[i].hashCode, states[i].hashCode);
      expect(states[i].toString(), isNotEmpty);
    }
    expect(const TripIdle().hashCode, const TripIdle().hashCode);
    expect(const TripStarting().journeyPhase, JourneyPhase.routePreview);
    expect(const TripEnding().journeyPhase, JourneyPhase.navigating);
    expect(const TripTransit().journeyPhase, JourneyPhase.idle);
    expect(const TripParkingLeg().guidanceRunning, isFalse);
  });

  test('TripMachine notifies only real changes', () {
    final machine = TripMachine();
    addTearDown(machine.dispose);
    var notified = 0;
    machine.addListener(() => notified++);
    machine.dispatch(const PlaceChosen());
    machine.dispatch(const PlaceChosen());
    expect(machine.value, const TripPlaceSelected());
    expect(notified, 1);
    expect(machine.dispatch(const NavigationStarted()), machine.value);
    expect(notified, 1);
  });

  group('RequestGeneration', () {
    test('a newer request or invalidate makes older tokens stale', () {
      final generation = RequestGeneration();
      final first = generation.next();
      expect(first.isCurrent, isTrue);
      final second = generation.next();
      expect(first.isStale, isTrue);
      expect(second.isCurrent, isTrue);
      final observer = generation.current;
      expect(observer.isCurrent, isTrue);
      expect(second.isCurrent, isTrue, reason: 'current does not supersede');
      generation.invalidate();
      expect(second.isStale, isTrue);
      expect(observer.isStale, isTrue);
    });

    test('Latest delivers only the newest result', () async {
      final latest = Latest<int>();
      final slow = latest.run((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 1;
      });
      final fast = latest.run((token) async {
        expect(token.isCurrent, isTrue);
        return 2;
      });
      expect(await fast, 2);
      expect(await slow, isNull);
      final failing = latest.run((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        throw StateError('superseded failure');
      });
      latest.cancel();
      expect(await failing, isNull);
      expect(
        () => latest.run((_) async => throw StateError('latest failure')),
        throwsStateError,
      );
    });
  });
}
