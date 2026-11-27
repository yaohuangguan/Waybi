import 'package:flutter/foundation.dart';

import '../domain/map_provider.dart' show JourneyPhase;

/// What the route preview is doing while it is on screen.
enum PreviewActivity {
  /// Showing a plan; the user can start.
  ready,

  /// Recalculating (new stop, mode or language); the old plan stays visible.
  reloading,

  /// Fetching public-transport itineraries for the Transit tab.
  loadingTransit,

  /// Asking for a route around a closure.
  findingDetour,
}

/// The single state of the home screen's trip, replacing a set of booleans
/// that could contradict each other (busy and ending, previewing and
/// navigating, ...). Data (the place, the plan, the route) lives in the
/// controllers; this says which of them is in charge.
@immutable
sealed class TripState {
  const TripState();

  /// Turn-by-turn guidance is running (including while it shuts down).
  bool get guidanceRunning => false;

  /// Buttons that would start another trip are disabled.
  bool get busy => false;

  /// The place card or preview is waiting for routes.
  bool get previewLoading => false;

  /// The coarse phase the map camera and analytics use.
  JourneyPhase get journeyPhase => JourneyPhase.idle;
}

/// Just the map.
final class TripIdle extends TripState {
  const TripIdle();

  @override
  bool operator ==(Object other) => other is TripIdle;
  @override
  int get hashCode => (TripIdle).hashCode;
  @override
  String toString() => 'TripIdle';
}

/// A place card. [routing]: its first route preview is being calculated.
final class TripPlaceSelected extends TripState {
  const TripPlaceSelected({this.routing = false});
  final bool routing;

  @override
  bool get previewLoading => routing;
  @override
  JourneyPhase get journeyPhase => JourneyPhase.placeSelected;
  @override
  bool operator ==(Object other) =>
      other is TripPlaceSelected && other.routing == routing;
  @override
  int get hashCode => Object.hash(TripPlaceSelected, routing);
  @override
  String toString() => 'TripPlaceSelected(routing: $routing)';
}

/// The route preview sheet.
final class TripPreviewing extends TripState {
  const TripPreviewing([this.activity = PreviewActivity.ready]);
  final PreviewActivity activity;

  @override
  bool get busy => activity == PreviewActivity.findingDetour;
  @override
  bool get previewLoading =>
      activity == PreviewActivity.reloading ||
      activity == PreviewActivity.loadingTransit;
  @override
  JourneyPhase get journeyPhase => JourneyPhase.routePreview;
  @override
  bool operator ==(Object other) =>
      other is TripPreviewing && other.activity == activity;
  @override
  int get hashCode => Object.hash(TripPreviewing, activity);
  @override
  String toString() => 'TripPreviewing($activity)';
}

/// Navigation (or a transit trip) is starting; the preview is still shown
/// and closing it cancels the start.
final class TripStarting extends TripState {
  const TripStarting();

  @override
  bool get busy => true;
  @override
  JourneyPhase get journeyPhase => JourneyPhase.routePreview;
  @override
  bool operator ==(Object other) => other is TripStarting;
  @override
  int get hashCode => (TripStarting).hashCode;
  @override
  String toString() => 'TripStarting';
}

/// Turn-by-turn guidance. [arrival]: close enough for the arrival panel.
final class TripNavigating extends TripState {
  const TripNavigating({this.arrival = false});
  final bool arrival;

  @override
  bool get guidanceRunning => true;
  @override
  JourneyPhase get journeyPhase => JourneyPhase.navigating;
  @override
  bool operator ==(Object other) =>
      other is TripNavigating && other.arrival == arrival;
  @override
  int get hashCode => Object.hash(TripNavigating, arrival);
  @override
  String toString() => 'TripNavigating(arrival: $arrival)';
}

/// Guidance is shutting down (engine stop, journey bookkeeping).
final class TripEnding extends TripState {
  const TripEnding();

  @override
  bool get guidanceRunning => true;
  @override
  JourneyPhase get journeyPhase => JourneyPhase.navigating;
  @override
  bool operator ==(Object other) => other is TripEnding;
  @override
  int get hashCode => (TripEnding).hashCode;
  @override
  String toString() => 'TripEnding';
}

/// Following a public-transport itinerary.
final class TripTransit extends TripState {
  const TripTransit();

  @override
  bool operator ==(Object other) => other is TripTransit;
  @override
  int get hashCode => (TripTransit).hashCode;
  @override
  String toString() => 'TripTransit';
}

/// Just Drive (no route). [starting]: the drive engine is starting.
final class TripJustDrive extends TripState {
  const TripJustDrive({this.starting = false});
  final bool starting;

  @override
  bool get busy => starting;
  @override
  bool operator ==(Object other) =>
      other is TripJustDrive && other.starting == starting;
  @override
  int get hashCode => Object.hash(TripJustDrive, starting);
  @override
  String toString() => 'TripJustDrive(starting: $starting)';
}

/// Parked at the chosen car park: offers to continue to the destination on
/// foot.
final class TripParkingLeg extends TripState {
  const TripParkingLeg();

  @override
  bool operator ==(Object other) => other is TripParkingLeg;
  @override
  int get hashCode => (TripParkingLeg).hashCode;
  @override
  String toString() => 'TripParkingLeg';
}

/// Something that happened to the trip.
@immutable
sealed class TripEvent {
  const TripEvent();
}

/// A place was chosen (map, search, shortcut, link).
final class PlaceChosen extends TripEvent {
  const PlaceChosen();
}

/// The place and any preview were dismissed.
final class PlaceCleared extends TripEvent {
  const PlaceCleared();
}

/// A route preview (or reload) started calculating.
final class PreviewRequested extends TripEvent {
  const PreviewRequested();
}

/// Public-transport itineraries started loading for the preview.
final class TransitLoadStarted extends TripEvent {
  const TransitLoadStarted();
}

/// A detour around a closure started calculating.
final class DetourStarted extends TripEvent {
  const DetourStarted();
}

/// Preview work finished. [hasPlan]: a plan is on screen (a failed first
/// load returns to the place card; a failed reload keeps the old plan).
final class PreviewSettled extends TripEvent {
  const PreviewSettled({required this.hasPlan});
  final bool hasPlan;
}

/// Back from the preview to its place card.
final class PreviewClosed extends TripEvent {
  const PreviewClosed();
}

/// The user pressed Start.
final class StartRequested extends TripEvent {
  const StartRequested();
}

/// The start failed or stopped early; the preview is usable again.
final class StartAborted extends TripEvent {
  const StartAborted();
}

/// Guidance is running.
final class NavigationStarted extends TripEvent {
  const NavigationStarted();
}

/// The remaining distance crossed the arrival-panel threshold.
final class ArrivalChanged extends TripEvent {
  const ArrivalChanged(this.arrival);
  final bool arrival;
}

/// Ending guidance started.
final class EndRequested extends TripEvent {
  const EndRequested();
}

/// Guidance ended. [parkingLeg]: it ended at the chosen car park.
final class NavigationEnded extends TripEvent {
  const NavigationEnded({this.parkingLeg = false});
  final bool parkingLeg;
}

/// A public-transport trip started.
final class TransitTripStarted extends TripEvent {
  const TransitTripStarted();
}

/// The public-transport trip ended.
final class TransitTripEnded extends TripEvent {
  const TransitTripEnded();
}

/// Just Drive is starting.
final class DriveRequested extends TripEvent {
  const DriveRequested();
}

/// Just Drive is running.
final class DriveStarted extends TripEvent {
  const DriveStarted();
}

/// Just Drive could not start, or was stopped.
final class DriveEnded extends TripEvent {
  const DriveEnded();
}

/// The parking-continuation card was dismissed.
final class ParkingLegDismissed extends TripEvent {
  const ParkingLegDismissed();
}

/// The only way the trip state changes. Events that do not apply to the
/// current state (a late answer after the user moved on) leave it unchanged.
TripState transition(TripState state, TripEvent event) {
  final active =
      state is TripNavigating ||
      state is TripEnding ||
      state is TripTransit ||
      state is TripJustDrive;
  return switch (event) {
    PlaceChosen() => active ? state : const TripPlaceSelected(),
    PlaceCleared() => active ? state : const TripIdle(),
    PreviewRequested() => switch (state) {
      TripPlaceSelected() => const TripPlaceSelected(routing: true),
      TripPreviewing() => const TripPreviewing(PreviewActivity.reloading),
      _ => state,
    },
    TransitLoadStarted() =>
      state is TripPreviewing
          ? const TripPreviewing(PreviewActivity.loadingTransit)
          : state,
    DetourStarted() =>
      state is TripPreviewing
          ? const TripPreviewing(PreviewActivity.findingDetour)
          : state,
    PreviewSettled(:final hasPlan) => switch (state) {
      TripPlaceSelected() || TripPreviewing() =>
        hasPlan ? const TripPreviewing() : const TripPlaceSelected(),
      _ => state,
    },
    PreviewClosed() =>
      state is TripPreviewing ||
              state is TripStarting ||
              state is TripPlaceSelected
          ? const TripPlaceSelected()
          : state,
    StartRequested() => switch (state) {
      TripPreviewing(activity: PreviewActivity.findingDetour) => state,
      TripPreviewing() => const TripStarting(),
      _ => state,
    },
    StartAborted() => state is TripStarting ? const TripPreviewing() : state,
    NavigationStarted() =>
      state is TripStarting ? const TripNavigating() : state,
    ArrivalChanged(:final arrival) =>
      state is TripNavigating ? TripNavigating(arrival: arrival) : state,
    EndRequested() => state is TripNavigating ? const TripEnding() : state,
    NavigationEnded(:final parkingLeg) =>
      state is TripNavigating || state is TripEnding
          ? (parkingLeg ? const TripParkingLeg() : const TripIdle())
          : state,
    TransitTripStarted() => state is TripStarting ? const TripTransit() : state,
    TransitTripEnded() => state is TripTransit ? const TripIdle() : state,
    DriveRequested() =>
      state is TripNavigating || state is TripEnding || state is TripTransit
          ? state
          : const TripJustDrive(starting: true),
    DriveStarted() => state is TripJustDrive ? const TripJustDrive() : state,
    DriveEnded() => state is TripJustDrive ? const TripIdle() : state,
    ParkingLegDismissed() => state is TripParkingLeg ? const TripIdle() : state,
  };
}

/// Holds the [TripState]; [dispatch] is the only writer.
class TripMachine extends ValueNotifier<TripState> {
  TripMachine([super.value = const TripIdle()]);

  /// Applies [event]; listeners hear only real changes.
  TripState dispatch(TripEvent event) => value = transition(value, event);
}
