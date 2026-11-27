import './style.css';

import { cameraLabel, distanceMeters, formatDistance, matchCamerasToRoute, nearestOnRoute, type Camera, type Coordinate, type Route, type RouteCamera, type RouteStep } from '@waybi/core';
import './account.css';
import { applyUiLanguage, formatDuration, localeFor, plural, t, type MessageKey } from './i18n';
import { applyTheme, readLanguage, readTheme, writeLanguage, writeTheme, LANGUAGE_EVENT, type ThemePreference } from './preferences';
import { currentAccountEmail, initAccount, isSignedIn, ownReview, recentDestinations, rememberDestination, rememberPreferences, rememberRoute, renderAccount, saveOwnReview, savePlace, savedPlace, type AccountProfile } from './account';
import { lookAheadCenter } from './navigation-view';
import { initAutocomplete, placeLabel, type SuggestedPlace } from './autocomplete';
import { WaybiMapAdapter, type PoiSelection } from './waybi-map';
import { fetchRoutePlan, routeFromOption, type RouteOption as PlannerRouteOption, type RoutePlan as PlannerRoutePlan, type TravelMode } from './route-planner';
import type { ParkingPlace } from './parking';
import { apiFetch, describeError, isAbortError } from './api';
import { closeDialog, openDialog } from './dialogs';
import { registerUpdates } from './pwa';
import { lockupSvg } from './brand';
import { currentPlatform, isStandalone, permissionHelpKey } from './geo-help';
import { RouteRequestCoordinator, journeySummaryKind, layoutSignature, type PlanTrigger } from './route-requests';

type Language = 'zh' | 'en';
type Place = SuggestedPlace;
type CameraResponse = { cameras: Camera[]; sourceUpdatedAt: string; checkedAt: string | null; syncStatus: string; syncError?: string | null; change?: { added: number; removed: number } };
const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
// The router keeps the map shell hidden until this chunk (and its CSS) has loaded.
$('app').hidden = false;
applyTheme();
const map = new WaybiMapAdapter();
let cameras: Camera[] = [];
let cameraResponse: CameraResponse | null = null;
let routeCameras: RouteCamera[] = [];
let current: Coordinate | null = null;
let currentPlaceLabel = '';
let placeLookupStarted = false;
let latestHeading: number | null = null;
let deviceHeading: number | null = null;
let compassListening = false;
let lastCompassPaint = 0;
let manualOrigin: Coordinate | null = null;
let destination: Coordinate | null = null;
let destinationName = '';
let route: Route | null = null;
let drivingAlternatives: Route[] = [];
let selectedDrivingRoute = 0;
let routePlan: PlannerRoutePlan | null = null;
let drivingFromPlanner = false;
let trafficLayerEnabled = true;
let selectedTravelMode: TravelMode = 'drive';
const routeStops: { label: string; coordinate: Coordinate }[] = [];
let navigating = false;
let uiMode: 'explore' | 'navigation' = 'explore';
let following = true;
// One language key shared with the website and the dashboard (legacy keys are migrated).
let language: Language = readLanguage();
let voiceEnabled = localStorage.getItem('kiwi-voice') !== 'off';
let keepScreenAwake = localStorage.getItem('kiwi-keep-screen-awake') !== 'off';
let journeyStarted = 0;
let journeyDistance = 0;
let journeyPoints: Coordinate[] = [];
let arrivalWithinRadiusAt = 0;
let latestGpsFixAt = 0;
let laneGuidanceEnabled = localStorage.getItem('kiwi-lane-guidance') !== 'off';
let searchTarget: 'origin' | 'destination' | 'stop' = 'destination';
const routeRequests = new RouteRequestCoordinator();
let lastRerouteAt = 0;
let rerouteTimer = 0;
let rerouteStatusTimer = 0;
type RerouteStatus = { kind: 'rerouting' } | { kind: 'offline' | 'retry' | 'busy'; until: number };
let rerouteStatus: RerouteStatus | null = null;
let lastTurnKey = '';
let wakeLock: WakeLockSentinel | null = null;
let toastTimeout = 0;
type TripState = 'stateCalculating' | 'stateRouteReady' | 'stateRouteError' | 'stateDriving' | 'stateGuidance' | 'stateReady' | 'stateArrived' | 'stateParkingReached';
let tripState: TripState = 'stateReady';
type GpsStatus = 'idle' | 'locating' | 'active' | 'denied' | 'unavailable';
let gpsStatus: GpsStatus = 'idle';
let gpsAccuracy: number | null = null;
let gpsWatchId: number | null = null;
let gpsRequesting = false;
let selectedPoi: PoiSelection | null = null;
let currentSpeedKph = 0;
let speedLimitKph: number | null = null;
let lastSpeedLimitLookupAt = 0;
let lastSpeedLimitCoordinate: Coordinate | null = null;
let speedLimitLookupPending = false;
const spokenCameras = new Set<string>();

type ParkingDestination = { coordinate: Coordinate; name: string };
let parkingDestination: ParkingDestination | null = null;
let parkingPlaces: ParkingPlace[] = [];
let selectedParking: ParkingPlace | null = null;
let parkingLoading = false;
let parkingError: MessageKey | '' = '';
let parkingSearchSequence = 0;
let parkedAtParking = false;

function setDestinationSelection(coordinate: Coordinate, name: string) {
  ++parkingSearchSequence;
  parkingDestination = null;
  selectedParking = null;
  parkedAtParking = false;
  parkingPlaces = [];
  parkingLoading = false;
  parkingError = '';
  selectedTravelMode = 'drive';
  destination = coordinate;
  destinationName = name;
  map.renderParking([], null, selectParking);
  renderParking();
  void loadParking();
}

async function loadParking() {
  const target = destination;
  if (!target || parkingDestination) return;
  const request = ++parkingSearchSequence;
  parkingLoading = true;
  parkingError = '';
  renderParking();
  try {
    const official = await api<{ places: ParkingPlace[] }>(
      `/api/parking?at=${target[0]},${target[1]}`
    ).catch(() => null);
    const places = official?.places?.length ? official.places : await map.searchParking(target);
    if (request !== parkingSearchSequence || !destination || parkingDestination) return;
    parkingPlaces = places;
    parkingError = '';
  } catch {
    if (request !== parkingSearchSequence) return;
    parkingPlaces = [];
    parkingError = 'parkingUnavailable';
  } finally {
    if (request === parkingSearchSequence) {
      parkingLoading = false;
      renderParking();
    }
  }
}

function selectParking(place: ParkingPlace) {
  if (navigating || !destination) return;
  if (!parkingDestination) parkingDestination = { coordinate: destination, name: destinationName };
  selectedParking = place;
  parkedAtParking = false;
  destination = place.coordinate;
  destinationName = place.name;
  selectedTravelMode = 'drive';
  map.renderParking(parkingPlaces, place.id, selectParking);
  renderParking();
  if (manualOrigin || current) void planRoute();
}

function driveToDestination() {
  if (!parkingDestination) return;
  destination = parkingDestination.coordinate;
  destinationName = parkingDestination.name;
  parkingDestination = null;
  selectedParking = null;
  parkedAtParking = false;
  selectedTravelMode = 'drive';
  map.renderParking(parkingPlaces, null, selectParking);
  renderParking();
  if (manualOrigin || current) void planRoute();
}

function continueOnFoot() {
  if (!parkingDestination || !selectedParking || !parkedAtParking) return;
  destination = parkingDestination.coordinate;
  destinationName = parkingDestination.name;
  parkingDestination = null;
  selectedParking = null;
  parkedAtParking = false;
  parkingPlaces = [];
  selectedTravelMode = 'walk';
  routeStops.splice(0, routeStops.length);
  manualOrigin = null;
  renderStops();
  map.renderParking([], null, selectParking);
  route = null;
  drivingAlternatives = [];
  routePlan = null;
  map.clearRoute();
  ($('driveButton') as HTMLButtonElement).disabled = true;
  $('travelModes').hidden = true;
  $('routeAlternatives').hidden = true;
  renderParking();
  if (current) void planRoute('walk');
  else requestGps();
}

function renderParking() {
  const section = $('parkingSection');
  const hint = $('navParkingHint');
  section.hidden = !destination || selectedTravelMode !== 'drive';
  $('navDestinationLabel').textContent = t(language, selectedParking && selectedTravelMode === 'drive' ? 'parkingStop' : 'destinationLabel');
  hint.hidden = !selectedParking || !parkingDestination || selectedTravelMode !== 'drive';
  if (section.hidden) {
    map.renderParking([], null, selectParking);
    return;
  }
  const target = parkingDestination || { coordinate: destination!, name: destinationName };
  const isAtSource = parkingPlaces[0]?.source === 'at';
  $('parkingSourceNote').textContent = t(language, isAtSource ? 'parkingSourceAt' : 'parkingSourceSearch');
  const sourceLink = $('parkingSourceLink') as HTMLAnchorElement;
  sourceLink.hidden = !isAtSource;
  $('parkingSummary').textContent = selectedParking
    ? t(language, 'parkingSelectedSummary', { parking: selectedParking.name, distance: formatDistance(selectedParking.distanceMeters, language), destination: target.name })
    : t(language, 'parkingIntro');
  if (!hint.hidden) hint.textContent = t(language, 'parkingHint', { parking: selectedParking!.name, destination: target.name });
  const list = $('parkingList');
  list.replaceChildren();
  if (parkingLoading && !parkingPlaces.length) {
    list.textContent = t(language, 'parkingLoading');
  } else if (parkingError && !parkingPlaces.length) {
    list.textContent = t(language, parkingError);
  } else if (!parkingPlaces.length) {
    list.textContent = t(language, 'parkingNone');
  } else {
    for (const place of parkingPlaces) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'parking-option' + (place.id === selectedParking?.id ? ' selected' : '');
      button.setAttribute('aria-pressed', String(place.id === selectedParking?.id));
      const icon = document.createElement('span');
      icon.className = 'parking-option-icon';
      icon.setAttribute('aria-hidden', 'true');
      icon.textContent = 'P';
      const copy = document.createElement('span');
      copy.className = 'parking-option-copy';
      const name = document.createElement('strong');
      name.textContent = place.name;
      const address = document.createElement('small');
      address.textContent = place.address || t(language, 'parkingPlace');
      copy.append(name, address);
      if (place.source === 'at') {
        const details = document.createElement('small');
        details.className = 'parking-option-detail';
        details.textContent = [
          place.totalSpaces !== null ? t(language, 'parkingTotalSpaces', { count: place.totalSpaces }) : '',
          place.mobilitySpaces !== null ? t(language, 'parkingAccessible', { count: place.mobilitySpaces }) : '',
          place.clearanceMeters !== null ? t(language, 'parkingClearance', { meters: place.clearanceMeters }) : ''
        ].filter(Boolean).join(' · ') || 'AT Open GIS';
        copy.append(details);
      }
      const distance = document.createElement('span');
      distance.className = 'parking-option-distance';
      distance.textContent = formatDistance(place.distanceMeters, language);
      button.append(icon, copy, distance);
      button.onclick = () => selectParking(place);
      list.append(button);
    }
  }
  const actions = $('parkingActions');
  actions.replaceChildren();
  actions.hidden = !selectedParking;
  if (selectedParking) {
    const direct = document.createElement('button');
    direct.type = 'button';
    direct.textContent = t(language, 'parkingDriveDirect');
    direct.onclick = driveToDestination;
    actions.append(direct);
    const detailsUrl = selectedParking.source === 'at'
      ? 'https://at.govt.nz/driving-and-parking/find-parking'
      : selectedParking.sourceUrl;
    if (detailsUrl) {
      const details = document.createElement('a');
      details.href = detailsUrl;
      details.target = '_blank';
      details.rel = 'noopener noreferrer';
      details.textContent = t(language, selectedParking.source === 'at' ? 'parkingRates' : 'parkingDetails');
      actions.append(details);
    }
    if (parkedAtParking) {
      const walk = document.createElement('button');
      walk.type = 'button';
      walk.className = 'primary';
      walk.textContent = t(language, 'parkingWalk');
      walk.onclick = continueOnFoot;
      actions.prepend(walk);
    }
  }
  map.renderParking(parkingPlaces, selectedParking?.id || null, selectParking);
}


function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char] || char);
}

function toast(message: string, duration = 4500) {
  const element = $('toast');
  element.textContent = message;
  element.hidden = false;
  window.clearTimeout(toastTimeout);
  // Longer messages stay a little longer so they can be read.
  toastTimeout = window.setTimeout(() => { element.hidden = true; }, Math.max(duration, Math.min(10000, message.length * 70)));
}

const API_BASE_URL = '';

function api<T>(path: string, signal?: AbortSignal): Promise<T> {
  return apiFetch<T>(`${API_BASE_URL}${path}`, { signal });
}

function renderTripFlags() {
  $('sheetVoice').textContent = t(language, voiceEnabled ? 'voiceOn' : 'voiceOff');
  $('sheetLane').textContent = t(language, laneGuidanceEnabled ? 'lanesOn' : 'lanesOff');
  $('sheetAccount').textContent = t(language, isSignedIn() ? 'accountSynced' : 'guestMode');
  const voiceChip = $('navVoiceChip');
  const lanesChip = $('navLanesChip');
  voiceChip.textContent = t(language, voiceEnabled ? 'voiceOn' : 'voiceOff');
  lanesChip.textContent = t(language, laneGuidanceEnabled ? 'lanesOn' : 'lanesOff');
  voiceChip.setAttribute('aria-pressed', String(voiceEnabled));
  lanesChip.setAttribute('aria-pressed', String(laneGuidanceEnabled));
}

function setUiMode(next: 'explore' | 'navigation') {
  uiMode = next;
  document.body.dataset.mode = next;
  $('navBanner').hidden = next !== 'navigation';
  $('navSheet').hidden = next !== 'navigation';
  $('bottomPanel').hidden = next === 'navigation';
  $('searchPanel').hidden = next === 'navigation';
  if (next === 'navigation') {
    hidePoiCard();
    $('navSecondary').hidden = true;
    $('navSheetHandle').setAttribute('aria-expanded', 'false');
    document.body.classList.remove('nav-sheet-expanded');
    $('navSheetHandle').setAttribute('aria-label', t(language, 'showTripDetails'));
    requestAnimationFrame(updateNavigationOverlayLayout);
  }
}

function updateNavigationOverlayLayout() {
  updateMapViewport();
  if (uiMode !== 'navigation') return;
  document.body.style.setProperty('--nav-sheet-clearance', `${Math.ceil($('navSheet').getBoundingClientRect().height) + 12}px`);
  const bannerBottom = Math.ceil($('navBanner').getBoundingClientRect().bottom);
  document.body.style.setProperty('--nav-camera-top', `${bannerBottom + 8}px`);
  const camera = $('cameraAlert');
  const topBottom = camera.hidden ? bannerBottom : Math.ceil(camera.getBoundingClientRect().bottom);
  document.body.style.setProperty('--nav-banner-clearance', `${topBottom + 18}px`);
}

// Keep provider attribution inside the visible map viewport above mobile sheets.
function updateMapViewport() {
  const sheet = $(uiMode === 'navigation' ? 'navSheet' : 'bottomPanel');
  const clearance = window.innerWidth < 760 && !sheet.hidden
    ? Math.max(0, window.innerHeight - sheet.getBoundingClientRect().top) : 0;
  $('map').style.bottom = `${Math.ceil(clearance)}px`;
}
const mapViewportObserver = new ResizeObserver(updateMapViewport);
for (const id of ['bottomPanel', 'navSheet']) {
  mapViewportObserver.observe($(id));
  $(id).addEventListener('transitionend', updateMapViewport);
}
window.addEventListener('resize', updateNavigationOverlayLayout);
const navigationHeaderObserver = new ResizeObserver(() => requestAnimationFrame(updateNavigationOverlayLayout));
for (const id of ['navBanner', 'cameraAlert']) navigationHeaderObserver.observe($(id));

function renderSpeedHud() {
  const hud = $('speedHud');
  const speeding = speedLimitKph !== null && currentSpeedKph > speedLimitKph;
  hud.classList.toggle('speeding', speeding);
  $('speedValue').textContent = String(Math.round(currentSpeedKph));
  $('speedLimitValue').textContent = speedLimitKph === null
    ? t(language, 'speedLimitUnknown')
    : t(language, 'speedLimitBadge', { value: speedLimitKph });
  $('sheetSpeedLimit').textContent = speedLimitKph === null ? '—' : `${speedLimitKph} km/h`;
  $('navSpeedLimit').textContent = speedLimitKph === null ? '—' : `${speedLimitKph} km/h`;
}

async function refreshSpeedLimit(coordinate: Coordinate) {
  if (speedLimitLookupPending) return;
  const moved = lastSpeedLimitCoordinate ? distanceMeters(lastSpeedLimitCoordinate, coordinate) : Infinity;
  if (Date.now() - lastSpeedLimitLookupAt < 15000 && moved < 75) return;
  speedLimitLookupPending = true;
  lastSpeedLimitLookupAt = Date.now();
  lastSpeedLimitCoordinate = coordinate;
  try {
    const result = await api<{ speedLimitKph: number | null }>(
      `/api/speed-limit?at=${coordinate[0]},${coordinate[1]}`
    );
    speedLimitKph = Number.isFinite(result.speedLimitKph) ? result.speedLimitKph : null;
    renderSpeedHud();
  } catch (error) {
    // Keep the last known legal limit if the lookup fails; when rate limited,
    // do not ask again before retry-after.
    const failure = describeError(error);
    if (failure.rateLimited) lastSpeedLimitLookupAt = Date.now() + (failure.retryAfterMs || 60_000);
  } finally {
    speedLimitLookupPending = false;
  }
}

function renderCameras() {
  const onRoute = new Set(routeCameras.map((item) => item.camera.id));
  map.renderCameras(cameras, onRoute);
  $('cameraRouteCount').textContent = route ? String(routeCameras.length) : '—';
  $('navCameraCount').textContent = route ? String(routeCameras.length) : '—';
  if (!$('cameraList').hidden) renderCameraList();
}

/**
 * Keyboard and screen-reader route to the camera markers (which are kept out
 * of the Tab order): cameras on the current route, or the closest ones to the
 * map centre.
 */
function renderCameraList() {
  const root = $('cameraList');
  root.replaceChildren();
  const heading = document.createElement('p');
  heading.className = 'camera-list-heading';
  const items: { camera: Camera; distance: number }[] = route && routeCameras.length
    ? routeCameras.map((item) => ({ camera: item.camera, distance: Math.max(0, item.alongMeters) }))
    : (() => {
      const center = map.getCenter() || current || [174.7633, -36.8485] as Coordinate;
      return cameras.map((camera) => ({ camera, distance: distanceMeters(center, [camera.longitude, camera.latitude]) }))
        .sort((a, b) => a.distance - b.distance).slice(0, 12);
    })();
  heading.textContent = `${t(language, route && routeCameras.length ? 'cameraListRoute' : 'cameraListNearby')} · ${t(language, 'cameraListHint')}`;
  root.append(heading);
  if (!items.length) {
    const empty = document.createElement('p');
    empty.className = 'camera-list-empty';
    empty.textContent = t(language, 'cameraListEmpty');
    root.append(empty);
    return;
  }
  const list = document.createElement('ul');
  for (const { camera, distance } of items) {
    const item = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = t(language, 'cameraListItem', { label: cameraLabel(camera.type, language), location: camera.location, distance: formatDistance(distance, language) });
    button.onclick = () => {
      following = false;
      $('followButton').classList.remove('active');
      map.showCamera(camera.id);
    };
    item.append(button);
    list.append(item);
  }
  root.append(list);
}

function renderCameraStatus() {
  if (!cameraResponse) return;
  $('dataStatus').textContent = `${cameras.length} ${t(language, 'cameraCount')} · ${cameraResponse.sourceUpdatedAt}${cameraResponse.syncStatus === 'live' ? '' : ` · ${t(language, 'cached')}`}`;
  $('sourceDate').textContent = cameraResponse.sourceUpdatedAt;
  $('checkedAt').textContent = cameraResponse.checkedAt ? new Date(cameraResponse.checkedAt).toLocaleString(localeFor(language)) : t(language, 'neverChecked');
  $('syncStatus').textContent = t(language, cameraResponse.syncStatus === 'live' ? 'synced' : cameraResponse.syncStatus === 'stale' ? 'stale' : cameraResponse.syncStatus === 'offline' ? 'offline' : 'seed');
}

async function loadCameras() {
  try {
    const data = await api<CameraResponse>('/api/cameras');
    if (!Array.isArray(data.cameras) || data.cameras.length < 50) throw new Error('Camera data failed validation');
    cameraResponse = data;
    cameras = data.cameras;
    localStorage.setItem('kiwi-cameras', JSON.stringify(data));
  } catch {
    try {
      const cached = JSON.parse(localStorage.getItem('kiwi-cameras') || 'null') as CameraResponse | null;
      if (cached?.cameras?.length) { cameraResponse = { ...cached, syncStatus: 'offline' }; cameras = cached.cameras; }
    } catch { /* ignore damaged local cache */ }
  }
  if (cameraResponse) {
    renderCameraStatus();
    if (route) routeCameras = matchCamerasToRoute(cameras, route);
    renderCameras();
  } else $('dataStatus').textContent = t(language, 'camerasUnavailable');
}

function onDeviceOrientation(event: DeviceOrientationEvent) {
  const iosHeading = (event as DeviceOrientationEvent & { webkitCompassHeading?: number }).webkitCompassHeading;
  const measured = Number.isFinite(iosHeading)
    ? iosHeading!
    : event.absolute && event.alpha !== null ? 360 - event.alpha : null;
  if (measured === null || !Number.isFinite(measured)) return;
  const next = (measured + 360) % 360;
  if (deviceHeading !== null && Math.abs(((next - deviceHeading + 540) % 360) - 180) < 2 && Date.now() - lastCompassPaint < 200) return;
  deviceHeading = next;
  lastCompassPaint = Date.now();
  if (!current) return;
  map.setRadarHeading(deviceHeading);
  if (following) map.setFollowHeading(deviceHeading);
  map.setPosition(current, deviceHeading);
}

function listenToCompass() {
  if (compassListening) return;
  compassListening = true;
  window.addEventListener('deviceorientation', onDeviceOrientation);
  window.addEventListener('deviceorientationabsolute', onDeviceOrientation as EventListener);
}

function requestCompassFromGesture() {
  if (typeof DeviceOrientationEvent === 'undefined') return;
  const orientation = DeviceOrientationEvent as typeof DeviceOrientationEvent & { requestPermission?: (absolute?: boolean) => Promise<'granted' | 'denied'> };
  if (!orientation.requestPermission) { listenToCompass(); return; }
  if (compassListening) return;
  void orientation.requestPermission(true).then((result) => {
    if (result === 'granted') listenToCompass();
  }).catch(() => { /* GPS course remains the fallback. */ });
}

function updatePosition(latitude: number, longitude: number, heading: number | null, accuracy: number, speedMetersPerSecond?: number | null) {
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
      latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return;
  const previous = current;
  const now = Date.now();
  latestGpsFixAt = now;
  current = [longitude, latitude];
  if (navigating && Number.isFinite(accuracy) && accuracy >= 0 && accuracy <= 25) {
    if (previous) {
      const moved = distanceMeters(previous, current);
      if (moved > 2 && moved < 150) journeyDistance += moved;
    }
    journeyPoints.push([...current] as Coordinate);
  }

  latestHeading = heading;
  if (!placeLookupStarted) {
    placeLookupStarted = true;
    void api<{ label: string }>(`/api/reverse?at=${longitude},${latitude}&provider=independent`).then(({ label }) => {
      currentPlaceLabel = label;
      ($('originInput') as HTMLInputElement).placeholder = `${t(language, 'currentPlace')}: ${label}`;
      $('gpsBadge').title = label;
      toast(`${t(language, 'currentPlace')}: ${label}`);
    }).catch(() => { /* GPS coordinates remain available if reverse lookup fails */ });
  }
  gpsStatus = 'active';
  gpsAccuracy = accuracy;
  renderGpsStatus();
  currentSpeedKph = Number.isFinite(speedMetersPerSecond) && (speedMetersPerSecond || 0) > 0
    ? (speedMetersPerSecond || 0) * 3.6
    : 0;
  renderSpeedHud();
  void refreshSpeedLimit(current);
  const mapHeading = deviceHeading ?? heading;
  map.setRadarHeading(mapHeading);
  map.setPosition(current, mapHeading);
  if (following) {
    const center = navigating && route ? lookAheadCenter(current, heading, route) : current;
    if (navigating && route) map.focusNavigation(center);
    else map.setView(center, 15);
    map.setFollowHeading(mapHeading);
  }
  // A GPS fix only starts a plan when none is in flight and no failure backoff is running.
  if (destination && !route && !manualOrigin) void planRoute(undefined, 'auto');
  if (navigating && route) updateGuidance();
}

function renderGpsStatus() {
  const badge = $('gpsBadge');
  const text = $('gpsBadgeText');
  badge.classList.toggle('error', gpsStatus === 'denied' || gpsStatus === 'unavailable');
  if (gpsStatus === 'active' && gpsAccuracy !== null) text.textContent = t(language, 'gpsAccuracyBadge', { meters: Math.round(gpsAccuracy) });
  else if (gpsStatus === 'locating') text.textContent = t(language, 'locating');
  else if (gpsStatus === 'denied') text.textContent = t(language, 'permissionDenied');
  else if (gpsStatus === 'unavailable') text.textContent = t(language, 'gpsTemporary');
  else text.textContent = t(language, 'enableLocation');
  $('sheetGps').textContent = gpsStatus === 'active' && gpsAccuracy !== null
    ? `±${Math.round(gpsAccuracy)} m`
    : '—';
  $('navGpsChip').textContent = gpsStatus === 'active' && gpsAccuracy !== null
    ? t(language, 'gpsChip', { meters: Math.round(gpsAccuracy) }) : t(language, 'gpsUnknownChip');
}

function handleGpsError(error: GeolocationPositionError) {
  if (error.code === error.PERMISSION_DENIED && gpsWatchId !== null) {
    navigator.geolocation.clearWatch(gpsWatchId);
    gpsWatchId = null;
  }
  gpsStatus = error.code === error.PERMISSION_DENIED ? 'denied' : 'unavailable';
  gpsAccuracy = null;
  renderGpsStatus();
  if (error.code === error.PERMISSION_DENIED) toast(t(language, permissionHelpKey(currentPlatform(), isStandalone())), 9000);
}

function startGpsWatch() {
  if (!navigator.geolocation || gpsWatchId !== null) return;
  gpsStatus = 'locating';
  renderGpsStatus();
  gpsWatchId = navigator.geolocation.watchPosition(
    ({ coords }) => updatePosition(coords.latitude, coords.longitude, Number.isFinite(coords.heading) ? coords.heading : null, coords.accuracy, coords.speed),
    handleGpsError,
    { enableHighAccuracy: true, maximumAge: 1000, timeout: 18000 }
  );
}

function requestGps() {
  if (!navigator.geolocation) {
    gpsStatus = 'unavailable';
    renderGpsStatus();
    return;
  }
  if (gpsRequesting || gpsStatus === 'active') return;
  gpsRequesting = true;
  gpsStatus = 'locating';
  renderGpsStatus();
  navigator.geolocation.getCurrentPosition(
    ({ coords }) => {
      gpsRequesting = false;
      updatePosition(coords.latitude, coords.longitude, Number.isFinite(coords.heading) ? coords.heading : null, coords.accuracy, coords.speed);
      startGpsWatch();
    },
    (error) => {
      gpsRequesting = false;
      handleGpsError(error);
    },
    { enableHighAccuracy: true, maximumAge: 0, timeout: 18000 }
  );
}

/**
 * Starts tracking only when location was already granted. The permission
 * prompt itself is only ever shown from a user gesture (GPS badge, "use my
 * location", recenter, choosing a destination or starting navigation).
 */
async function initGps() {
  if (!navigator.geolocation) {
    gpsStatus = 'unavailable';
    renderGpsStatus();
    return;
  }
  if (!('permissions' in navigator)) { gpsStatus = 'idle'; renderGpsStatus(); return; }
  try {
    const permission = await navigator.permissions.query({ name: 'geolocation' as PermissionName });
    if (permission.state === 'granted') startGpsWatch();
    else {
      gpsStatus = permission.state === 'denied' ? 'denied' : 'idle';
      renderGpsStatus();
    }
    permission.onchange = () => {
      if (permission.state === 'granted') startGpsWatch();
      else {
        if (gpsWatchId !== null) {
          navigator.geolocation.clearWatch(gpsWatchId);
          gpsWatchId = null;
        }
        gpsStatus = permission.state === 'denied' ? 'denied' : 'idle';
        gpsAccuracy = null;
        renderGpsStatus();
      }
    };
  } catch {
    // Older Safari does not expose geolocation through the Permissions API.
    gpsStatus = 'idle';
    renderGpsStatus();
  }
}

function renderStops() {
  const editor = $('stopEditor');
  const list = $('stopList');
  list.replaceChildren();
  routeStops.forEach((stop, index) => {
    const chip = document.createElement('div');
    chip.className = 'stop-chip';
    const label = document.createElement('span');
    label.textContent = `${index + 1}. ${stop.label}`;
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.textContent = '×';
    remove.onclick = () => {
      routeStops.splice(index, 1);
      renderStops();
      if (destination && (manualOrigin || current)) void planRoute();
    };
    chip.append(label, remove);
    list.append(chip);
  });
  editor.hidden = routeStops.length === 0 && document.activeElement !== $('stopInput');
}

function selectedPlannerOption(): PlannerRouteOption | null {
  if (!routePlan) return null;
  const options = routePlan.options.filter((option) => option.mode === selectedTravelMode);
  if (selectedTravelMode === 'drive') return options[selectedDrivingRoute] || options[0] || null;
  return options[0] || null;
}

function trafficVisuals() {
  const plannerDriving = routePlan?.options.filter((option) => option.mode === 'drive') || [];
  return drivingAlternatives.map((fallback, index) => ({
    route: fallback,
    trafficIntervals: drivingFromPlanner ? plannerDriving[index]?.trafficIntervals || [] : []
  }));
}

function renderRouteInfo(option: PlannerRouteOption | null) {
  const root = $('routeInfoCards');
  const navCard = $('navTrafficCard');
  root.replaceChildren();
  root.hidden = true;
  navCard.hidden = true;
  navCard.replaceChildren();
  if (!option) return;
  if (option.mode === 'drive' && !option.trafficIntervals.length) {
    const card = document.createElement('div');
    card.className = 'route-info-card';
    card.textContent = t(language, 'trafficUnavailable');
    root.append(card);
    root.hidden = false;
  }

  if (option.mode === 'drive' && (option.traffic.slow > 0 || option.traffic.trafficJam > 0 || option.warnings.length)) {
    const card = document.createElement('div');
    card.className = 'route-info-card warning';
    const jam = option.traffic.trafficJam;
    const slow = option.traffic.slow;
    const message = jam > 0
      ? plural(language, jam, 'heavySectionsOne', 'heavySectionsOther')
      : slow > 0 ? plural(language, slow, 'slowSectionsOne', 'slowSectionsOther') : t(language, 'roadAdvisory');
    card.innerHTML = `<strong>⚠ ${escapeHtml(t(language, 'trafficAdvisory'))}</strong><span>${escapeHtml(message)}${option.warnings[0] ? ` · ${escapeHtml(option.warnings[0])}` : ''}</span>`;
    root.append(card);
    root.hidden = false;
    navCard.textContent = `⚠ ${message}${option.warnings[0] ? ` · ${option.warnings[0]}` : ''}`;
    navCard.hidden = false;
  }

  if (option.mode === 'transit' && option.transit.length) {
    for (const leg of option.transit) {
      const card = document.createElement('div');
      card.className = 'route-info-card transit';
      const title = [leg.lineName, leg.headsign].filter(Boolean).join(' → ') || leg.vehicleName || leg.vehicleType || t(language, 'transitFallback');
      const details = [leg.departureStop, leg.arrivalStop].filter(Boolean).join(' → ');
      const stops = leg.stopCount ? ` · ${plural(language, leg.stopCount, 'transitStopsOne', 'transitStopsOther')}` : '';
      card.innerHTML = `<strong>🚆 ${escapeHtml(title)}</strong><span>${escapeHtml(details)}${escapeHtml(stops)}</span>`;
      root.append(card);
    }
    root.hidden = false;
  }
}

function applyDrivingRoute(index: number) {
  const next = drivingAlternatives[index];
  if (!next || !destination) return;
  selectedDrivingRoute = index;
  route = next;
  routeCameras = matchCamerasToRoute(cameras, route);
  renderCameras();
  map.renderRoute(route, destination, navigating);
  map.setTrafficEnabled(trafficLayerEnabled);
  map.renderTrafficRoutes(trafficVisuals(), selectedDrivingRoute, (chosen) => {
    if (chosen === selectedDrivingRoute || navigating) return;
    applyDrivingRoute(chosen);
    renderRoutePlanner();
  });
  $('tripDistance').textContent = formatDistance(route.distance, language);
  $('tripArrival').textContent = new Date(Date.now() + route.duration * 1000).toLocaleTimeString(
    localeFor(language),
    { hour: '2-digit', minute: '2-digit' }
  );
  $('navDistance').textContent = $('tripDistance').textContent;
  $('navArrival').textContent = $('tripArrival').textContent;
  $('navCameraCount').textContent = String(routeCameras.length);
  $('cameraRouteCount').textContent = String(routeCameras.length);
  $('navRouteSteps').textContent = String(route.steps.length);
  $('sheetRouteSteps').textContent = String(route.steps.length);
  ($('driveButton') as HTMLButtonElement).disabled = false;
}

function renderRoutePlanner() {
  const modes = $('travelModes');
  const alternatives = $('routeAlternatives');
  const actions = $('planningActions');
  modes.hidden = !routePlan && drivingAlternatives.length === 0;
  actions.hidden = modes.hidden;
  $('trafficLegend').hidden = modes.hidden || selectedTravelMode !== 'drive' || !routePlan?.trafficAvailable;
  if (modes.hidden) {
    alternatives.hidden = true;
    $('routeInfoCards').hidden = true;
    return;
  }

  const modeIds: Record<TravelMode, string> = {
    drive: 'modeDriveTime',
    transit: 'modeTransitTime',
    walk: 'modeWalkTime',
    bicycle: 'modeBicycleTime'
  };
  for (const mode of ['drive', 'transit', 'walk', 'bicycle'] as TravelMode[]) {
    const option = routePlan?.options.find((item) => item.mode === mode);
    $(modeIds[mode]).textContent = mode === 'drive' && drivingAlternatives[0]
      ? formatDuration(drivingAlternatives[0].duration, language)
      : formatDuration(option?.durationSeconds, language);
    const button = modes.querySelector<HTMLButtonElement>(`button[data-mode="${mode}"]`);
    if (button) {
      const available = mode !== 'transit';
      button.disabled = !available;
      button.classList.toggle('selected', selectedTravelMode === mode);
      button.setAttribute('aria-pressed', String(selectedTravelMode === mode));
    }
  }

  alternatives.replaceChildren();
  if (selectedTravelMode === 'drive') {
    drivingAlternatives.forEach((item, index) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'route-option-card' + (selectedDrivingRoute === index ? ' selected' : '');
      button.setAttribute('aria-pressed', String(selectedDrivingRoute === index));
      button.innerHTML = `<strong>${escapeHtml(formatDuration(item.duration, language))}</strong><span>${escapeHtml(formatDistance(item.distance, language))}${index === 0 ? ` · ${escapeHtml(t(language, 'recommended'))}` : ''}</span>`;
      button.onclick = () => {
        applyDrivingRoute(index);
        renderRoutePlanner();
      };
      alternatives.append(button);
    });
    alternatives.hidden = drivingAlternatives.length < 2;
    renderRouteInfo(selectedPlannerOption());
    ($('driveButton') as HTMLButtonElement).disabled = drivingAlternatives.length === 0;
    $('driveLabel').textContent = t(language, 'startShort');
    return;
  }

  const option = selectedPlannerOption();
  if (option) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'route-option-card selected';
    button.innerHTML = `<strong>${escapeHtml(formatDuration(option.durationSeconds, language))}</strong><span>${escapeHtml(formatDistance(option.distanceMeters, language))}</span>`;
    alternatives.append(button);
    alternatives.hidden = false;
    if (destination) {
      const preview = routeFromOption(option);
      route = preview;
      routeCameras = [];
      map.clearTrafficRoutes();
      map.setTrafficEnabled(false);
      if (preview.coordinates.length >= 2) map.renderRoute(preview, destination, navigating);
    }
    $('tripDistance').textContent = formatDistance(option.distanceMeters, language);
    $('tripArrival').textContent = new Date(Date.now() + option.durationSeconds * 1000).toLocaleTimeString(
      localeFor(language),
      { hour: '2-digit', minute: '2-digit' }
    );
    $('cameraRouteCount').textContent = '—';
    $('navCameraCount').textContent = '—';
    ($('driveButton') as HTMLButtonElement).disabled = route?.coordinates.length ? false : true;
    $('driveLabel').textContent = t(language, selectedTravelMode === 'transit' ? 'startTrip' : 'startShort');
  } else {
    alternatives.hidden = true;
    ($('driveButton') as HTMLButtonElement).disabled = true;
  }
  renderRouteInfo(option);
}

function searchInput(target: 'origin' | 'destination' | 'stop') {
  return $(target === 'origin' ? 'originInput' : target === 'stop' ? 'stopInput' : 'destinationInput') as HTMLInputElement;
}

/** Applies a place chosen from suggestions or full search results. */
function selectPlace(target: 'origin' | 'destination' | 'stop', place: Place) {
  const coordinate: Coordinate = [place.longitude, place.latitude];
  const shortLabel = place.label.split(',').slice(0, 2).join(',');
  if (target === 'origin') {
    manualOrigin = coordinate;
    ($('originInput') as HTMLInputElement).value = shortLabel;
  } else if (target === 'stop') {
    routeStops.push({ label: shortLabel, coordinate });
    ($('stopInput') as HTMLInputElement).value = '';
    renderStops();
  } else {
    setDestinationSelection(coordinate, shortLabel);
    ($('destinationInput') as HTMLInputElement).value = destinationName;
    $('clearDestinationButton').hidden = false;
    void rememberDestination({ label: place.label, latitude: place.latitude, longitude: place.longitude });
  }
  if (destination && (manualOrigin || current)) void planRoute();
  else if (destination) { requestGps(); toast(t(language, 'chooseOrigin')); }
}

async function search(target: 'origin' | 'destination' | 'stop') {
  searchTarget = target;
  const input = searchInput(target);
  const query = input.value.trim();
  if (query.length < 3) { toast(t(language, 'minQuery')); return; }
  // Claiming the results panel cancels any pending suggestion debounce or
  // request, so a late suggestion can never replace these results.
  const token = autocomplete.begin(input);
  autocomplete.showMessage(input, t(language, 'searching'));
  try {
    const near = manualOrigin || current;
    const params = new URLSearchParams({ q: query, lang: language, provider: 'independent' });
    if (near) params.set('near', near.join(','));
    const places = await api<Place[]>(`/api/search?${params}`);
    if (!autocomplete.isCurrent(token)) return;
    if (!places.length) { autocomplete.showMessage(input, t(language, 'noResults')); return; }
    autocomplete.renderPlaces(input, places, (place) => selectPlace(target, place));
  } catch (error) {
    if (isAbortError(error) || !autocomplete.isCurrent(token)) return;
    const failure = describeError(error);
    const retry = () => void search(target);
    // Server error text is never shown (5xx bodies are generic and English); use localised copy.
    if (failure.offline) autocomplete.showMessage(input, t(language, 'searchOffline'), retry);
    else if (failure.busy) autocomplete.showMessage(input, t(language, 'searchBusy', { seconds: Math.ceil((failure.retryAfterMs || 30000) / 1000) }), retry);
    else autocomplete.showMessage(input, t(language, 'searchFailedRetry'), retry);
  }
}

function secondsUntil(until: number) { return Math.max(1, Math.ceil((until - Date.now()) / 1000)); }

/** Non-blocking navigation status shown in the trip sheet while a reroute is pending or failing. */
function renderRerouteStatus() {
  const node = $('navStatus');
  window.clearTimeout(rerouteStatusTimer);
  if (!rerouteStatus || !navigating) { node.hidden = true; node.textContent = ''; node.removeAttribute('data-kind'); return; }
  node.hidden = false;
  node.dataset.kind = rerouteStatus.kind;
  if (rerouteStatus.kind === 'rerouting') { node.textContent = t(language, 'rerouting'); return; }
  const key = rerouteStatus.kind === 'offline' ? 'rerouteOffline' : rerouteStatus.kind === 'busy' ? 'rerouteBusy' : 'rerouteRetry';
  node.textContent = t(language, key, { seconds: secondsUntil(rerouteStatus.until) });
  // Keep the countdown honest without re-rendering every frame.
  rerouteStatusTimer = window.setTimeout(renderRerouteStatus, 1000);
}

function setRerouteStatus(next: RerouteStatus | null) {
  rerouteStatus = next;
  renderRerouteStatus();
  requestAnimationFrame(updateNavigationOverlayLayout);
}

function clearRerouteRetry() {
  window.clearTimeout(rerouteTimer);
  rerouteTimer = 0;
}

function isOffRoute() {
  if (!current || !route) return false;
  return nearestOnRoute(current, route.coordinates).offsetMeters > 100;
}

function scheduleRerouteRetry(delay: number) {
  clearRerouteRetry();
  rerouteTimer = window.setTimeout(() => {
    rerouteTimer = 0;
    if (!navigating || manualOrigin) return;
    if (!isOffRoute()) { setRerouteStatus(null); routeRequests.backoff.succeed(); return; }
    lastRerouteAt = Date.now();
    void planRoute(undefined, 'reroute');
  }, delay + 50);
}

function setTripState(state: TripState) {
  tripState = state;
  $('tripEyebrow').textContent = t(language, state);
}

async function planRoute(modeOverride?: TravelMode, trigger: PlanTrigger = 'user') {
  const from = manualOrigin || current;
  if (!from || !destination) return;
  if (!routeRequests.canStart(trigger)) return;
  const controller = routeRequests.begin(trigger);
  const signal = controller.signal;
  const rerouting = navigating && trigger !== 'user';
  const requestedMode = modeOverride || selectedTravelMode;
  if (rerouting) setRerouteStatus({ kind: 'rerouting' });
  else {
    setTripState('stateCalculating');
    $('tripTitle').textContent = t(language, 'routeCalculating');
    ($('driveButton') as HTMLButtonElement).disabled = true;
  }
  try {
    const stopCoordinates = routeStops.map((stop) => stop.coordinate);
    const planner = await fetchRoutePlan(API_BASE_URL, from, destination, stopCoordinates, signal, requestedMode, language);
    if (signal.aborted || !routeRequests.isCurrent(controller)) return;
    const usable = planner.options.filter(option => routeFromOption(option).coordinates.length >= 2);
    if (!usable.some(option => option.mode === requestedMode)) throw new Error(t(language, 'noRouteAvailable'));
    routeRequests.succeed(controller);
    clearRerouteRetry();
    routePlan = planner;
    drivingAlternatives = usable.filter(option => option.mode === 'drive').map(routeFromOption);
    drivingFromPlanner = true;
    selectedDrivingRoute = 0;
    selectedTravelMode = requestedMode;
    if (requestedMode === 'drive') applyDrivingRoute(0);
    setTripState(navigating ? 'stateDriving' : 'stateRouteReady');
    $('tripTitle').textContent = destinationName || t(language, 'destinationFallback');
    $('navDestinationTitle').textContent = destinationName || t(language, 'destinationFallback');
    $('sheetNextCamera').textContent = routeCameras.length
      ? formatDistance(Math.max(0, routeCameras[0]!.alongMeters), language)
      : '—';
    $('navNextCamera').textContent = $('sheetNextCamera').textContent;
    renderRoutePlanner();
    renderParking();
    if (navigating) {
      setRerouteStatus(null);
      if (selectedTravelMode !== 'drive') document.body.dataset.travelMode = selectedTravelMode;
      updateGuidance();
    }
  } catch (error) {
    if (isAbortError(error) || signal.aborted || !routeRequests.isCurrent(controller)) return;
    const failure = describeError(error);
    const { delay, notify } = routeRequests.fail(controller, failure.retryAfterMs);
    if (navigating) {
      // Never end a trip because a reroute failed: keep guiding along the last
      // known route and retry quietly until the user ends navigation.
      setRerouteStatus({ kind: failure.offline ? 'offline' : failure.busy ? 'busy' : 'retry', until: Date.now() + delay });
      scheduleRerouteRetry(delay);
      return;
    }
    route = null;
    routePlan = null;
    drivingAlternatives = [];
    routeCameras = [];
    map.clearRoute();
    renderRoutePlanner();
    ($('driveButton') as HTMLButtonElement).disabled = true;
    setTripState('stateRouteError');
    $('tripTitle').textContent = t(language, 'routeError');
    // One message per failure streak; GPS-triggered retries stay silent.
    if (notify) {
      if (failure.busy) toast(t(language, 'routeBusy', { seconds: Math.ceil(delay / 1000) }));
      else if (failure.offline) toast(t(language, 'routeOffline'));
      else toast(t(language, failure.status >= 400 && failure.status < 500 ? 'noRouteAvailable' : 'routeFailedRetry'));
    }
  }
}

function clearDestination() {
  ++parkingSearchSequence;
  parkingDestination = null;
  selectedParking = null;
  parkedAtParking = false;
  parkingPlaces = [];
  parkingLoading = false;
  parkingError = '';
  map.renderParking([], null, selectParking);
  $('parkingSection').hidden = true;
  $('navParkingHint').hidden = true;
  routeRequests.reset();
  clearRerouteRetry();
  destination = null;
  destinationName = '';
  route = null;
  drivingAlternatives = [];
  selectedDrivingRoute = 0;
  routePlan = null;
  drivingFromPlanner = false;
  selectedTravelMode = 'drive';
  routeStops.splice(0, routeStops.length);
  routeCameras = [];
  lastTurnKey = '';
  spokenCameras.clear();

  ($('destinationInput') as HTMLInputElement).value = '';
  autocomplete.cancel();
  autocomplete.close();
  $('stopEditor').hidden = true;
  $('travelModes').hidden = true;
  $('routeAlternatives').hidden = true;
  $('routeInfoCards').hidden = true;
  $('trafficLegend').hidden = true;
  $('planningActions').hidden = true;
  $('navTrafficCard').hidden = true;
  renderStops();
  $('clearDestinationButton').hidden = true;
  ($('driveButton') as HTMLButtonElement).disabled = true;

  setTripState('stateReady');
  $('tripTitle').textContent = t(language, 'initialTitle');
  $('tripDistance').textContent = '—';
  $('tripArrival').textContent = '—';
  $('cameraRouteCount').textContent = '—';
  $('sheetNextCamera').textContent = '—';
  $('sheetRouteSteps').textContent = '—';
  $('navDestinationTitle').textContent = '—';
  $('navDistance').textContent = '—';
  $('navArrival').textContent = '—';
  $('navCameraCount').textContent = '—';
  $('navNextCamera').textContent = '—';
  $('navRouteSteps').textContent = '—';
  $('cameraAlert').hidden = true;

  map.clearRoute();
  renderCameras();
  if (current) map.setView(current, 15);
}

function saveCurrentRoute() {
  if (!destination || !destinationName) return;
  const saved = JSON.parse(sessionStorage.getItem('kiwi-saved-routes') || '[]') as unknown[];
  const record = {
    savedAt: new Date().toISOString(),
    destinationName,
    destination,
    mode: selectedTravelMode,
    stops: routeStops.map((stop) => ({ label: stop.label, coordinate: stop.coordinate })),
    distance: selectedTravelMode === 'drive' ? route?.distance ?? null : selectedPlannerOption()?.distanceMeters ?? null,
    duration: selectedTravelMode === 'drive' ? route?.duration ?? null : selectedPlannerOption()?.durationSeconds ?? null
  };
  const next = [record, ...saved.filter((item) => {
    if (!item || typeof item !== 'object') return true;
    return (item as { destinationName?: string }).destinationName !== destinationName;
  })].slice(0, 20);
  sessionStorage.setItem('kiwi-saved-routes', JSON.stringify(next));
  if (isSignedIn()) {
    void rememberRoute({
      destinationName, latitude: destination[1], longitude: destination[0], mode: selectedTravelMode,
      distanceMeters: record.distance, durationSeconds: record.duration
    }).then(() => toast(t(language, 'routeSavedAccount')))
      .catch((error) => toast(String(error)));
  } else toast(t(language, 'routeSavedSession'));
}

let speechGeneration = 0;
let speechQueue = Promise.resolve();
function stopSpeech() {
  speechGeneration++;
  if ('speechSynthesis' in window) speechSynthesis.cancel();
}
function speak(message: string, stillRelevant: () => boolean = () => true) {
  if (!voiceEnabled || !('speechSynthesis' in window)) return;
  const generation = speechGeneration;
  const speechLanguage = language;
  speechQueue = speechQueue.catch(() => {}).then(() => {
    if (!voiceEnabled || generation !== speechGeneration || !stillRelevant()) return;
    return new Promise<void>((resolve) => {
      const utterance = new SpeechSynthesisUtterance(message);
      utterance.lang = speechLanguage === 'zh' ? 'zh-CN' : 'en-NZ';
      utterance.rate = speechLanguage === 'zh' ? .95 : .9;
      const voices = speechSynthesis.getVoices();
      const preferred = voices.find((voice) => voice.lang.toLowerCase().startsWith(speechLanguage === 'zh' ? 'zh' : 'en-nz'))
        || voices.find((voice) => speechLanguage === 'en' && voice.lang.toLowerCase().startsWith('en'));
      if (preferred) utterance.voice = preferred;
      utterance.onend = () => resolve();
      utterance.onerror = (event) => {
        if (event.error !== 'canceled' && event.error !== 'interrupted') toast(t(speechLanguage, 'voiceFailed'));
        resolve();
      };
      speechSynthesis.resume();
      speechSynthesis.speak(utterance);
    });
  });
}

function turnText(step: RouteStep) {
  if (step.instruction?.trim() && (language !== 'zh' || /[\u3400-\u9fff]/.test(step.instruction))) return step.instruction;
  const modifier = step.modifier || '';
  const road = step.name || t(language, 'roadFallback');
  if (step.maneuver === 'arrive') return t(language, 'arrived');
  if (step.maneuver === 'roundabout' || step.maneuver === 'rotary') return t(language, 'turnRoundabout', { road });
  if (modifier.includes('left')) return t(language, 'turnLeft', { road });
  if (modifier.includes('right')) return t(language, 'turnRight', { road });
  if (step.maneuver === 'depart') return t(language, 'turnDepart', { road });
  return t(language, 'turnContinue', { road });
}

function turnArrow(step: RouteStep) {
  const modifier = step.modifier || '';
  if (modifier.includes('left')) return '↰';
  if (modifier.includes('right')) return '↱';
  if (step.maneuver === 'arrive') return '◆';
  if (step.maneuver === 'roundabout') return '↻';
  return '↑';
}

function laneSymbol(indications: string[]) {
  const symbols = indications.map((indication) => {
    if (indication.includes('uturn')) return '↶';
    if (indication.includes('sharp left')) return '↙';
    if (indication.includes('slight left')) return '↖';
    if (indication.includes('left')) return '←';
    if (indication.includes('sharp right')) return '↘';
    if (indication.includes('slight right')) return '↗';
    if (indication.includes('right')) return '→';
    if (indication.includes('straight')) return '↑';
    return '·';
  });
  return [...new Set(symbols)].join('');
}

function renderLaneGuidance(step?: RouteStep) {
  const root = $('laneGuidance');
  const lanes = laneGuidanceEnabled ? step?.lanes : undefined;
  if (!lanes?.length || !lanes.some((lane) => lane.valid)) {
    root.hidden = true;
    root.replaceChildren();
    return;
  }
  root.replaceChildren(...lanes.map((lane) => {
    const item = document.createElement('span');
    item.className = 'lane' + (lane.valid ? ' recommended' : '') + (lane.indications.length > 1 ? ' multi' : '');
    item.textContent = laneSymbol(lane.indications);
    item.setAttribute('aria-label', `${t(language, lane.valid ? 'laneRecommended' : 'laneLabel')}: ${lane.indications.join(', ') || t(language, 'laneUnknown')}`);
    return item;
  }));
  root.hidden = false;
}

function nextStep(progress: number) {
  if (!route) return null;
  const steps = route.steps.map((step) => ({ step, along: nearestOnRoute(step.location, route!.coordinates).alongMeters }));
  return steps.find((item) => item.along > progress + 20 && item.step.maneuver !== 'depart') || steps.at(-1) || null;
}

function updateGuidance() {
  if (!current || !route || !navigating) return;
  const nearExactDestination = destination && distanceMeters(current, destination) <= 10;
  const accurate = gpsAccuracy !== null && Number.isFinite(gpsAccuracy) && gpsAccuracy <= 25 && gpsAccuracy >= 0;
  if (nearExactDestination && accurate && Date.now() - latestGpsFixAt < 3000) {
    arrivalWithinRadiusAt ||= latestGpsFixAt;
    if (latestGpsFixAt - arrivalWithinRadiusAt >= 750) { stopNavigation(true); return; }
  } else arrivalWithinRadiusAt = 0;
  const position = nearestOnRoute(current, route.coordinates);
  if (position.offsetMeters > 100 && !manualOrigin && !rerouteTimer && Date.now() - lastRerouteAt > 20000 && routeRequests.canStart('reroute')) {
    lastRerouteAt = Date.now();
    void planRoute(undefined, 'reroute');
  } else if (position.offsetMeters <= 60 && rerouteStatus && rerouteStatus.kind !== 'rerouting') {
    // Back on the old route: the pending retry is no longer needed.
    clearRerouteRetry();
    routeRequests.backoff.succeed();
    setRerouteStatus(null);
  }
  const progress = position.alongMeters;
  const remaining = Math.max(0, route.distance - progress);
  const remainingSeconds = route.duration * remaining / Math.max(route.distance, 1);
  const maneuver = nextStep(progress);
  $('turnArrow').textContent = maneuver ? turnArrow(maneuver.step) : '◆';
  $('turnDistance').textContent = maneuver ? formatDistance(Math.max(0, maneuver.along - progress), language) : '—';
  $('turnInstruction').textContent = maneuver ? turnText(maneuver.step) : t(language, 'arrived');
  renderLaneGuidance(maneuver && maneuver.along - progress <= 300 ? maneuver.step : undefined);
  $('turnEta').textContent = new Date(Date.now() + remainingSeconds * 1000).toLocaleTimeString(localeFor(language), { hour: '2-digit', minute: '2-digit' });
  $('turnRemaining').textContent = formatDistance(remaining, language);
  $('tripDistance').textContent = formatDistance(remaining, language);
  $('tripArrival').textContent = $('turnEta').textContent;
  $('navDistance').textContent = $('turnRemaining').textContent;
  $('navArrival').textContent = $('turnEta').textContent;
  if (maneuver) {
    const toTurn = maneuver.along - progress;
    if (following) {
      const zoom = toTurn < 45 ? 19.2 : toTurn < 140 ? 18.4 : 17.2;
      const lookAhead = toTurn < 45 ? 35 : toTurn < 140 ? 60 : 150;
      map.focusNavigation(lookAheadCenter(current, latestHeading, route, lookAhead), zoom);
    }
    const key = `${language}:${maneuver.step.location.join(',')}:${toTurn <= 100 ? '100' : '500'}`;
    if (toTurn > 0 && toTurn <= 500 && key !== lastTurnKey) {
      lastTurnKey = key;
      speak(t(language, 'speakTurn', { distance: formatDistance(toTurn, language), instruction: turnText(maneuver.step) }), () => navigating && key === lastTurnKey);
    }
  }
  const upcoming = routeCameras.filter((item) => item.confidence === 'high' && item.alongMeters >= progress - 15).sort((a, b) => a.alongMeters - b.alongMeters)[0];
  $('sheetNextCamera').textContent = upcoming
    ? formatDistance(Math.max(0, upcoming.alongMeters - progress), language)
    : '—';
  $('navNextCamera').textContent = $('sheetNextCamera').textContent;
  if (upcoming && upcoming.alongMeters - progress <= 1200) {
    const ahead = Math.max(0, upcoming.alongMeters - progress);
    $('cameraAlert').hidden = false;
    $('alertType').textContent = cameraLabel(upcoming.camera.type, language);
    $('alertRoad').textContent = upcoming.camera.location;
    $('alertDistance').textContent = formatDistance(ahead, language);
    for (const threshold of [ahead <= 300 ? 300 : 800]) {
      const key = `${upcoming.camera.id}:${threshold}`;
      if (ahead <= threshold && ahead > 0 && !spokenCameras.has(key)) {
        spokenCameras.add(key);
        const label = cameraLabel(upcoming.camera.type, language);
        speak(t(language, 'speakCamera', { threshold, label, location: upcoming.camera.location }), () => navigating && current !== null && route !== null && upcoming.alongMeters > nearestOnRoute(current, route.coordinates).alongMeters);
      }
    }
  } else $('cameraAlert').hidden = true;
  requestAnimationFrame(updateNavigationOverlayLayout);

}

async function startNavigation() {
  if (!current) { requestGps(); toast(t(language, 'noGps')); return; }
  if (!route) { toast(t(language, 'routeError')); return; }
  navigating = true;
  $('updateBanner').hidden = true;
  journeyStarted = Date.now();
  journeyDistance = 0;
  journeyPoints = [[...current] as Coordinate];
  arrivalWithinRadiusAt = 0;
  spokenCameras.clear();
  following = true;
  requestCompassFromGesture();
  document.body.dataset.travelMode = selectedTravelMode;
  $('followButton').classList.add('active');
  setTripState(selectedTravelMode === 'drive' ? 'stateDriving' : 'stateGuidance');
  $('driveLabel').textContent = t(language, 'stop');
  $('driveIcon').textContent = '■';
  $('drivingStatus').textContent = t(language, 'drivingStarted');
  setUiMode('navigation');
  $('navDestinationTitle').textContent = destinationName || t(language, 'destinationFallback');
  const lookAhead = lookAheadCenter(current, latestHeading, route);
  map.focusNavigation(lookAhead);
  lastTurnKey = '';
  if (manualOrigin && current) { manualOrigin = null; void planRoute(); }
  speak(
    t(language, selectedTravelMode === 'transit' ? 'navStartedTransit' : 'navStarted')
  );
  await updateWakeLock();
  updateGuidance();
}

function stopNavigation(arrived = false) {
  if (!navigating) return;
  if (isSignedIn() && destination && route) {
    void rememberRoute({
      destinationName: destinationName || t(language, 'destinationFallback'), latitude: destination[1], longitude: destination[0],
      mode: selectedTravelMode, distanceMeters: route.distance, durationSeconds: route.duration
    }).catch(() => { /* Ending navigation must work even if account sync fails. */ });
  }
  navigating = false;
  clearRerouteRetry();
  setRerouteStatus(null);
  // A failed or pending reroute must not keep running after the trip ends.
  if (routeRequests.pendingTrigger !== 'user') routeRequests.cancel();
  routeRequests.backoff.succeed();
  stopSpeech();
  showJourneySummary(arrived);
  showUpdateBanner();
  delete document.body.dataset.travelMode;
  renderLaneGuidance();
  $('cameraAlert').hidden = true;
  setUiMode('explore');
  if (route) map.fitRoute(route);
  if (arrived && selectedParking && parkingDestination && selectedTravelMode === 'drive') {
    parkedAtParking = true;
    renderParking();
    setSheetCollapsed(false);
    requestAnimationFrame(() => $('parkingSection').scrollIntoView({ block: 'nearest', behavior: 'smooth' }));
  }
  setTripState(arrived ? (parkedAtParking ? 'stateParkingReached' : 'stateArrived') : 'stateRouteReady');
  $('driveLabel').textContent = t(language, 'start');
  $('driveIcon').textContent = '➤';
  $('drivingStatus').textContent = t(language, 'drivingStopped');
  void wakeLock?.release();
  wakeLock = null;
  if (arrived) speak(t(language, parkedAtParking ? 'arrivedParkingSpeech' : 'arrivedSpeech'));
}

function showDialog(id: string) { openDialog($(id) as HTMLDialogElement); }
function hideDialog(id: string) { closeDialog($(id) as HTMLDialogElement); }

function hidePoiCard() {
  selectedPoi = null;
  $('poiCard').hidden = true;
  document.body.classList.remove('poi-open');
}

function renderPoiAccountState(place: PoiSelection) {
  const stored = savedPlace(place.placeId);
  const signedIn = isSignedIn();
  const favorite = $('poiFavorite') as HTMLButtonElement;
  const note = $('poiNote') as HTMLTextAreaElement;
  const saveNote = $('poiSaveNote') as HTMLButtonElement;
  favorite.textContent = stored?.isFavorite ? '♥' : '♡';
  favorite.setAttribute('aria-pressed', String(stored?.isFavorite === true));
  favorite.setAttribute('aria-label', t(language, stored?.isFavorite ? 'poiFavoriteRemove' : 'poiFavorite'));
  favorite.classList.toggle('active', stored?.isFavorite === true);
  favorite.disabled = false;
  note.disabled = !signedIn;
  saveNote.disabled = !signedIn;
  note.value = stored?.note || '';
  const review = ownReview(place.placeId);
  const rating = $('poiOwnRating') as HTMLSelectElement;
  const comment = $('poiOwnComment') as HTMLTextAreaElement;
  const saveReview = $('poiSaveReview') as HTMLButtonElement;
  rating.value = String(review?.rating || 5);
  rating.disabled = !signedIn;
  comment.value = review?.comment || '';
  comment.disabled = !signedIn;
  saveReview.disabled = !signedIn;
  $('poiOwnReviewHint').textContent = t(language, signedIn ? 'poiReviewHintSignedIn' : 'poiReviewHintGuest');
  $('poiAccountHint').textContent = signedIn
    ? t(language, 'poiAccountHintSignedIn', { email: currentAccountEmail() })
    : t(language, 'poiAccountHintGuest');
}

function showPoiCard(place: PoiSelection) {
  if (uiMode === 'navigation') return;
  selectedPoi = place;
  $('poiTitle').textContent = place.name;
  $('poiType').textContent = place.primaryType || t(language, 'poiTypeFallback');
  $('poiAddress').textContent = place.address || `${place.coordinate[1].toFixed(5)}, ${place.coordinate[0].toFixed(5)}`;

  const rating = $('poiRating');
  if (place.rating !== null) {
    rating.replaceChildren();
    const stars = document.createElement('span');
    stars.className = 'stars';
    stars.textContent = '★'.repeat(Math.max(1, Math.min(5, Math.round(place.rating))));
    const text = document.createElement('span');
    text.textContent = t(language, 'poiRatings', { rating: place.rating.toFixed(1), count: place.userRatingCount ?? 0 });
    rating.append(stars, text);
    rating.hidden = false;
  } else rating.hidden = true;

  const summary = $('poiSummary');
  summary.textContent = place.editorialSummary;
  summary.hidden = !place.editorialSummary;

  const photos = $('poiPhotos');
  photos.replaceChildren();
  for (const photo of place.photos) {
    const figure = document.createElement('figure');
    figure.className = 'poi-photo';
    const image = document.createElement('img');
    image.src = photo.url;
    image.alt = photo.attribution ? `${place.name} · ${photo.attribution}` : place.name;
    image.loading = 'lazy';
    figure.append(image);
    if (photo.attribution) {
      const caption = document.createElement('figcaption');
      caption.textContent = `© ${photo.attribution}`;
      figure.append(caption);
    }
    photos.append(figure);
  }
  photos.hidden = place.photos.length === 0;

  const meta = $('poiMeta');
  meta.replaceChildren();
  const addMeta = (value: string) => {
    if (!value) return;
    const chip = document.createElement('span');
    chip.textContent = value;
    meta.append(chip);
  };
  addMeta(place.businessStatus === 'OPERATIONAL' ? t(language, 'poiOperational') : (place.businessStatus || ''));
  addMeta(place.priceLevel?.replaceAll('_', ' ') || '');
  addMeta(place.phone ? `☎ ${place.phone}` : '');

  const hours = $('poiHours');
  hours.replaceChildren();
  for (const line of place.openingHours) {
    const row = document.createElement('div');
    row.textContent = line;
    hours.append(row);
  }
  hours.hidden = place.openingHours.length === 0;

  const website = $('poiWebsite') as HTMLAnchorElement;
  website.hidden = !place.websiteURI;
  website.href = place.websiteURI || '#';
  const mapsLink = $('poiMapSource') as HTMLAnchorElement;
  mapsLink.hidden = !place.sourceUrl;
  mapsLink.href = place.sourceUrl || '#';

  const reviewsRoot = $('poiReviews');
  reviewsRoot.replaceChildren();
  for (const review of place.reviews) {
    const root = document.createElement('article');
    root.className = 'poi-review';
    const head = document.createElement('div');
    head.className = 'poi-review-head';
    if (review.authorPhoto) {
      const avatar = document.createElement('img');
      avatar.src = review.authorPhoto;
      avatar.alt = review.author;
      avatar.loading = 'lazy';
      head.append(avatar);
    }
    const author = document.createElement('strong');
    author.textContent = review.author;
    const score = document.createElement('span');
    score.textContent = `${review.rating ?? '—'} ★ · ${review.relativeTime}`;
    head.append(author, score);
    const copy = document.createElement('p');
    copy.textContent = review.text;
    root.append(head, copy);
    if (review.sourceUrl) {
      const link = document.createElement('a');
      link.className = 'source-link';
      link.href = review.sourceUrl;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      link.textContent = t(language, 'poiViewSource');
      root.append(link);
    }
    reviewsRoot.append(root);
  }
  $('poiReviewCount').textContent = place.userRatingCount ? String(place.userRatingCount) : '';
  $('poiReviewsSection').hidden = place.reviews.length === 0;

  renderPoiAccountState(place);
  $('poiCard').hidden = false;
  document.body.classList.add('poi-open');
  autocomplete.close();
}

async function saveSelectedPlace(nextFavorite?: boolean) {
  if (!selectedPoi) return;
  if (!isSignedIn()) {
    toast(t(language, 'signInToSync'));
    return;
  }
  const stored = savedPlace(selectedPoi.placeId);
  const note = ($('poiNote') as HTMLTextAreaElement).value.trim();
  const isFavorite = nextFavorite ?? stored?.isFavorite ?? false;
  try {
    await savePlace({
      placeId: selectedPoi.placeId,
      name: selectedPoi.name,
      address: selectedPoi.address,
      latitude: selectedPoi.coordinate[1],
      longitude: selectedPoi.coordinate[0],
      isFavorite,
      note
    });
    renderPoiAccountState(selectedPoi);
    renderTripFlags();
    toast(t(language, 'savedToAccount'));
  } catch (error) {
    toast(String((error as Error).message));
  }
}

function navigateToSelectedPoi() {
  if (!selectedPoi) return;
  setDestinationSelection(selectedPoi.coordinate, selectedPoi.name);
  ($('destinationInput') as HTMLInputElement).value = destinationName;
  $('clearDestinationButton').hidden = false;
  void rememberDestination({
    label: selectedPoi.address ? `${selectedPoi.name}, ${selectedPoi.address}` : selectedPoi.name,
    latitude: selectedPoi.coordinate[1],
    longitude: selectedPoi.coordinate[0]
  });
  hidePoiCard();
  if (manualOrigin || current) void planRoute();
  else {
    requestGps();
    toast(t(language, 'chooseOrigin'));
  }
}

const sheetQuery = window.matchMedia('(max-width: 759px)');
function sheetCollapsed() { return $('bottomPanel').classList.contains('sheet-collapsed'); }

/**
 * Keeps the sheet handle's state in sync and keeps the off-screen part of a
 * collapsed phone sheet out of the Tab order (inert).
 */
function renderSheetHandle() {
  const collapsed = sheetCollapsed() && sheetQuery.matches;
  const handle = $('sheetHandle');
  handle.setAttribute('aria-expanded', String(!collapsed));
  handle.setAttribute('aria-label', t(language, collapsed ? 'expandSheet' : 'collapseSheet'));
  $('sheetBody').toggleAttribute('inert', collapsed);
}

function setSheetCollapsed(collapsed: boolean) {
  $('bottomPanel').classList.toggle('sheet-collapsed', collapsed);
  renderSheetHandle();
}

function initBottomSheet() {
  const panel = $('bottomPanel');
  const handle = $('sheetHandle');
  if (sheetQuery.matches) panel.classList.add('sheet-collapsed');
  renderSheetHandle();
  sheetQuery.addEventListener?.('change', renderSheetHandle);

  let startY = 0;
  let latestY = 0;
  let dragging = false;
  let suppressClick = false;

  const finish = () => {
    if (!dragging) return;
    dragging = false;
    panel.classList.remove('sheet-dragging');
    const delta = latestY - startY;
    if (Math.abs(delta) < 18) setSheetCollapsed(!sheetCollapsed());
    else setSheetCollapsed(delta > 0);
    panel.style.transform = '';
    // The pointer gesture already toggled; ignore the click that follows it.
    suppressClick = true;
    window.setTimeout(() => { suppressClick = false; }, 0);
  };

  handle.addEventListener('pointerdown', (event) => {
    dragging = true;
    startY = event.clientY;
    latestY = event.clientY;
    panel.classList.add('sheet-dragging');
    handle.setPointerCapture?.(event.pointerId);
  });
  handle.addEventListener('pointermove', (event) => {
    if (!dragging) return;
    latestY = event.clientY;
    const delta = latestY - startY;
    const base = sheetCollapsed() ? Math.max(0, panel.offsetHeight - 108) : 0;
    panel.style.transform = `translateY(${Math.max(0, base + delta)}px)`;
  });
  handle.addEventListener('pointerup', finish);
  handle.addEventListener('pointercancel', finish);
  // Keyboard and assistive tech: Enter/Space toggle (click), arrows set the state.
  handle.addEventListener('click', () => {
    if (suppressClick) return;
    setSheetCollapsed(!sheetCollapsed());
  });
  handle.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowUp') { event.preventDefault(); setSheetCollapsed(false); }
    else if (event.key === 'ArrowDown') { event.preventDefault(); setSheetCollapsed(true); }
  });
}

async function saveSelectedReview() {
  if (!selectedPoi || !isSignedIn()) {
    toast(t(language, 'signInToReview'));
    return;
  }
  try {
    await saveOwnReview({
      placeId: selectedPoi.placeId,
      placeName: selectedPoi.name,
      rating: Number(($('poiOwnRating') as HTMLSelectElement).value),
      comment: ($('poiOwnComment') as HTMLTextAreaElement).value.trim()
    });
    renderPoiAccountState(selectedPoi);
    toast(t(language, 'reviewSaved'));
  } catch (error) { toast(String((error as Error).message)); }
}

$('originInput').addEventListener('focus', () => { searchTarget = 'origin'; });
$('destinationInput').addEventListener('focus', () => { searchTarget = 'destination'; });
$('stopInput').addEventListener('focus', () => { searchTarget = 'stop'; $('stopEditor').hidden = false; });
const autocomplete = initAutocomplete({
  origin: $('originInput') as HTMLInputElement,
  destination: $('destinationInput') as HTMLInputElement,
  extraInputs: [$('stopInput') as HTMLInputElement],
  results: $('searchResults'),
  language: () => language,
  recent: recentDestinations,
  near: () => manualOrigin || current,
  select: (target, place: SuggestedPlace) => selectPlace(target, place)
});
for (const [id, target] of [['originInput', 'origin'], ['destinationInput', 'destination'], ['stopInput', 'stop']] as const) {
  $(id).addEventListener('keydown', (event) => {
    // Enter on a highlighted suggestion is handled by the combobox.
    if ((event as KeyboardEvent).key === 'Enter' && !event.defaultPrevented) { event.preventDefault(); void search(target); }
  });
}
$('searchButton').onclick = () => void search('destination');
$('stopSearchButton').onclick = () => void search('stop');
$('useGpsButton').onclick = () => {
  manualOrigin = null;
  ($('originInput') as HTMLInputElement).value = '';
  if (!current) { requestGps(); return; }
  if (destination) void planRoute();
};
$('clearDestinationButton').onclick = clearDestination;
$('addStopButton').onclick = () => {
  $('stopEditor').hidden = false;
  ($('stopInput') as HTMLInputElement).focus();
};
$('saveRouteButton').onclick = saveCurrentRoute;
$('travelModes').addEventListener('click', (event) => {
  const button = (event.target as HTMLElement).closest<HTMLButtonElement>('button[data-mode]');
  if (!button || button.disabled) return;
  selectedTravelMode = button.dataset.mode as TravelMode;
  if (selectedTravelMode !== 'drive' && parkingDestination) {
    destination = parkingDestination.coordinate;
    destinationName = parkingDestination.name;
    parkingDestination = null;
    selectedParking = null;
    parkedAtParking = false;
    map.renderParking(parkingPlaces, null, selectParking);
    renderParking();
    void planRoute(selectedTravelMode);
    return;
  }
  void planRoute(selectedTravelMode);
});
$('driveButton').onclick = () => {
  if (navigating) stopNavigation();
  else void startNavigation();
};
$('navEndButton').onclick = () => stopNavigation();
$('navDataButton').onclick = () => showDialog('dataDialog');
$('poiClose').onclick = hidePoiCard;
$('poiNavigate').onclick = navigateToSelectedPoi;
$('poiFavorite').onclick = () => {
  if (!selectedPoi) return;
  void saveSelectedPlace(!(savedPlace(selectedPoi.placeId)?.isFavorite ?? false));
};
$('poiSaveNote').onclick = () => void saveSelectedPlace();
$('poiSaveReview').onclick = () => void saveSelectedReview();
$('followButton').onclick = () => { requestCompassFromGesture(); following = !following; $('followButton').classList.toggle('active', following); if (following && current) { map.setFollowHeading(deviceHeading ?? latestHeading); const center = navigating && route ? lookAheadCenter(current, latestHeading, route) : current; if (navigating) map.focusNavigation(center); else map.panTo(center); } };
$('recenterButton').onclick = () => {
  requestCompassFromGesture();
  if (!current) { requestGps(); return; }
  following = true;
  $('followButton').classList.add('active');
  const center = navigating && route ? lookAheadCenter(current, latestHeading, route) : current;
  if (navigating) map.focusNavigation(center);
  else map.setView(center, 16);
  map.setFollowHeading(deviceHeading ?? latestHeading);
};
$('navVoiceChip').onclick = () => {
  voiceEnabled = !voiceEnabled;
  localStorage.setItem('kiwi-voice', voiceEnabled ? 'on' : 'off');
  if (!voiceEnabled) stopSpeech();
  ($('voiceToggle') as HTMLInputElement).checked = voiceEnabled;
  renderTripFlags();
  void rememberPreferences(language, voiceEnabled);
};
$('navLanesChip').onclick = () => {
  laneGuidanceEnabled = !laneGuidanceEnabled;
  ($('laneToggle') as HTMLInputElement).checked = laneGuidanceEnabled;
  localStorage.setItem('kiwi-lane-guidance', laneGuidanceEnabled ? 'on' : 'off');
  renderTripFlags();
  updateGuidance();
};
$('navGpsChip').onclick = () => { if (current) ($('recenterButton') as HTMLButtonElement).click(); else requestGps(); };
$('trafficToggle').onclick = () => {
  trafficLayerEnabled = !trafficLayerEnabled;
  map.setTrafficEnabled(trafficLayerEnabled && selectedTravelMode === 'drive');
  $('trafficToggle').classList.toggle('active', trafficLayerEnabled);
  $('trafficToggle').setAttribute('aria-pressed', String(trafficLayerEnabled));
};
for (const [id, degrees] of [['rotateLeft', -45], ['rotateRight', 45]] as const) {
  $(id).onclick = () => {
    if (!map.rotateBy(degrees)) {
      toast(t(language, 'rotationUnavailable'));
      return;
    }
    following = false;
    $('followButton').classList.remove('active');
  };
}
$('navOverviewChip').onclick = () => {
  if (!route) return;
  following = false;
  $('followButton').classList.remove('active');
  map.fitRoute(route);
};
$('navSheetHandle').onclick = () => {
  const expanded = $('navSecondary').hidden;
  $('navSecondary').hidden = !expanded;
  document.body.classList.toggle('nav-sheet-expanded', expanded);
  $('navSheetHandle').setAttribute('aria-expanded', String(expanded));
  $('navSheetHandle').setAttribute('aria-label', t(language, expanded ? 'hideTripDetails' : 'showTripDetails'));
  requestAnimationFrame(updateNavigationOverlayLayout);
  if (current && route && navigating && following) requestAnimationFrame(() => map.focusNavigation(lookAheadCenter(current!, latestHeading, route!)));
};
$('settingsButton').onclick = () => showDialog('settingsDialog');
$('profileButton').onclick = () => { window.location.href = '/dashboard'; };
$('closeSettings').onclick = () => hideDialog('settingsDialog');
$('dataButton').onclick = () => showDialog('dataDialog');
$('cameraListButton').onclick = () => {
  const list = $('cameraList');
  list.hidden = !list.hidden;
  $('cameraListButton').setAttribute('aria-expanded', String(!list.hidden));
  if (!list.hidden) renderCameraList();
};
$('closeData').onclick = () => hideDialog('dataDialog');
function applyLanguage() {
  applyUiLanguage(language);
  for (const [id, code] of [['zhButton', 'zh'], ['enButton', 'en']] as const) {
    $(id).classList.toggle('selected', language === code);
    $(id).setAttribute('aria-pressed', String(language === code));
  }
  ($('originInput') as HTMLInputElement).placeholder = currentPlaceLabel ? `${t(language, 'currentPlace')}: ${currentPlaceLabel}` : t(language, 'origin');
  if (currentPlaceLabel) $('gpsBadge').title = currentPlaceLabel;
  $('tripEyebrow').textContent = t(language, tripState);
  $('driveLabel').textContent = navigating ? t(language, 'stop') : route ? t(language, selectedTravelMode === 'transit' ? 'startTrip' : 'startShort') : t(language, 'start');
  $('drivingStatus').textContent = t(language, navigating ? 'drivingStarted' : 'drivingStopped');
  $('navDestinationLabel').textContent = t(language, selectedParking && selectedTravelMode === 'drive' ? 'parkingStop' : 'destinationLabel');
  $('navSheetHandle').setAttribute('aria-label', t(language, $('navSecondary').hidden ? 'showTripDetails' : 'hideTripDetails'));
  if (route) $('navDestinationTitle').textContent = destinationName || t(language, 'destinationFallback');
  if (!route && !navigating && tripState === 'stateReady') $('tripTitle').textContent = t(language, 'initialTitle');
  if (tripState === 'stateRouteError') $('tripTitle').textContent = t(language, 'routeError');
  if (tripState === 'stateCalculating') $('tripTitle').textContent = t(language, 'routeCalculating');
  if (cameraResponse) renderCameraStatus();
  else $('dataStatus').textContent = t(language, 'camerasLoading');
  renderSheetHandle();
  renderCameras();
  renderAccount();
  renderGpsStatus();
  renderSpeedHud();
  renderTripFlags();
  renderParking();
  renderRerouteStatus();
  if (routePlan || drivingAlternatives.length) renderRoutePlanner();
  if (route) {
    $('tripDistance').textContent = formatDistance(navigating ? Math.max(0, route.distance - nearestOnRoute(current || route.coordinates[0]!, route.coordinates).alongMeters) : route.distance, language);
  }
  if (selectedPoi) showPoiCard(selectedPoi);
  if (navigating) updateGuidance();
}

/** Appearance: follow the system, or a light/dark choice shared with the website and dashboard. */
function renderThemeChoice(preference: ThemePreference = readTheme()) {
  for (const id of ['themeSystem', 'themeLight', 'themeDark']) {
    $(id).setAttribute('aria-pressed', String($(id).dataset.themeChoice === preference));
  }
}
for (const id of ['themeSystem', 'themeLight', 'themeDark']) {
  $(id).onclick = () => {
    const preference = $(id).dataset.themeChoice as ThemePreference;
    writeTheme(preference);
    renderThemeChoice(preference);
  };
}
renderThemeChoice();
window.matchMedia?.('(prefers-color-scheme: dark)').addEventListener?.('change', () => applyTheme());
$('zhButton').onclick = () => changeLanguage('zh');
$('enButton').onclick = () => changeLanguage('en');
($('voiceToggle') as HTMLInputElement).checked = voiceEnabled;
$('voiceToggle').addEventListener('change', () => {
  voiceEnabled = ($('voiceToggle') as HTMLInputElement).checked;
  localStorage.setItem('kiwi-voice', voiceEnabled ? 'on' : 'off');
  if (!voiceEnabled) stopSpeech();
  renderTripFlags();
  void rememberPreferences(language, voiceEnabled);
  if (voiceEnabled) speak(t(language, 'voiceOnSpeech'));
});
$('voiceTestButton').onclick = () => speak(t(language, 'voiceTestSpeech'));
($('laneToggle') as HTMLInputElement).checked = laneGuidanceEnabled;
$('laneToggle').addEventListener('change', () => {
  laneGuidanceEnabled = ($('laneToggle') as HTMLInputElement).checked;
  localStorage.setItem('kiwi-lane-guidance', laneGuidanceEnabled ? 'on' : 'off');
  renderTripFlags();
  if (navigating) updateGuidance(); else renderLaneGuidance();
});
document.addEventListener('visibilitychange', () => { if (!document.hidden) void updateWakeLock(); });
$('gpsBadge').onclick = () => { requestCompassFromGesture(); requestGps(); };
let lastLayout = layoutSignature(window.innerWidth, window.innerHeight);
window.addEventListener('resize', () => {
  // Keyboards and collapsing address bars resize the viewport constantly; only a
  // rotation or a breakpoint change should undo the user's own pan and zoom.
  const layout = layoutSignature(window.innerWidth, window.innerHeight);
  const changed = layout !== lastLayout;
  lastLayout = layout;
  if (!route) return;
  requestAnimationFrame(updateNavigationOverlayLayout);
  if (!changed) return;
  if (navigating && current && following) map.focusNavigation(lookAheadCenter(current, latestHeading, route));
  else if (uiMode === 'explore') map.fitRoute(route);
});
setUiMode('explore');
initBottomSheet();
renderSpeedHud();
renderTripFlags();
$('trafficToggle').hidden = true;

window.addEventListener(LANGUAGE_EVENT, (event) => {
  const next = (event as CustomEvent<Language>).detail;
  if ((next === 'en' || next === 'zh') && next !== language) changeLanguage(next, false);
});
window.addEventListener('storage', (event) => {
  if (event.key === 'waybi-ui-language' && (event.newValue === 'en' || event.newValue === 'zh') && event.newValue !== language) changeLanguage(event.newValue, false);
});
window.addEventListener('kiwi-account-change', () => {
  renderTripFlags();
  if (selectedPoi) renderPoiAccountState(selectedPoi);
});

// Offline shell and updates: a new version is offered, never forced. During
// navigation the prompt waits until the trip ends.
let applyUpdate: (() => void) | null = null;
function showUpdateBanner() {
  if (!applyUpdate || navigating) return;
  $('updateBanner').hidden = false;
}
registerUpdates((apply) => { applyUpdate = apply; showUpdateBanner(); });
$('updateReload').onclick = () => applyUpdate?.();
$('updateLater').onclick = () => { $('updateBanner').hidden = true; applyUpdate = null; };

async function initializeMap() {
  await map.init({
    language,
    onDragStart: () => {
      following = false;
      $('followButton').classList.remove('active');
    },
    onMapClick: () => {
      autocomplete.close();
      hidePoiCard();
    },
    onPoiSelected: showPoiCard
  });
  map.setTrafficEnabled(trafficLayerEnabled);
  renderParking();
  if (destination && !parkingDestination && !parkingPlaces.length) void loadParking();
}

void initializeMap().catch((error) => {
  toast(t(language, 'mapLoadFailed', { message: String((error as Error).message) }));
});

void initGps();
void loadCameras();
if (typeof DeviceOrientationEvent !== 'undefined' && !('requestPermission' in DeviceOrientationEvent)) listenToCompass();
window.setInterval(() => void loadCameras(), 15 * 60_000);

const accountRoot = $('accountSection');
applyLanguage();
void initAccount(accountRoot, () => language, () => voiceEnabled, (saved: AccountProfile) => {
  // The account's language is the source of truth once signed in; store it in
  // the shared key so the website and dashboard follow it too.
  if (saved.language === 'en' || saved.language === 'zh') changeLanguage(saved.language, false);
  voiceEnabled = saved.voiceEnabled;
  ($('voiceToggle') as HTMLInputElement).checked = voiceEnabled;
  applyLanguage();
  renderTripFlags();
  if (selectedPoi) renderPoiAccountState(selectedPoi);
});


let wakeLockRequest: Promise<void> | null = null;
async function updateWakeLock() {
  if (!navigating || !keepScreenAwake || document.hidden) {
    await wakeLock?.release(); wakeLock = null; return;
  }
  if ((wakeLock && !wakeLock.released) || wakeLockRequest) return;
  wakeLockRequest = (async () => {
    try {
      if ('wakeLock' in navigator) {
        const lock = await navigator.wakeLock.request('screen');
        if (!navigating || !keepScreenAwake || document.hidden) { await lock.release(); return; }
        wakeLock = lock;
        lock.addEventListener('release', () => { if (wakeLock === lock) wakeLock = null; });
      }
    } catch { /* Browser permission and foreground visibility apply. */ }
  })();
  try { await wakeLockRequest; } finally { wakeLockRequest = null; }
}

function changeLanguage(next: Language, persistToAccount = true) {
  if (next === language) { applyLanguage(); return; }
  language = next;
  writeLanguage(next);
  applyLanguage();
  if (persistToAccount) void rememberPreferences(language, voiceEnabled);
  // Map labels switch in place: destination, route, stops and navigation stay.
  map.setLanguage(next);
}

function showJourneySummary(arrived: boolean) {
  const elapsed = Date.now() - journeyStarted;
  const kind = journeySummaryKind(arrived, journeyDistance, elapsed);
  if (kind === 'none') { toast(t(language, 'navigationEnded')); return; }
  const root = $('journeySummaryDialog') as HTMLDialogElement;
  const points = journeyPoints.length ? journeyPoints : current ? [current] : [];
  const title = t(language, kind === 'arrived' ? 'journeyArrived' : 'journeyEnded');
  const minutes = Math.max(1, Math.round(elapsed / 60000));
  const minX = Math.min(...points.map(p => p[0])), maxX = Math.max(...points.map(p => p[0]));
  const minY = Math.min(...points.map(p => p[1])), maxY = Math.max(...points.map(p => p[1]));
  const aspect = Math.cos((minY + maxY) / 2 * Math.PI / 180);
  const scale = Math.min(300 / Math.max(.00001, (maxX - minX) * aspect), 140 / Math.max(.00001, maxY - minY));
  const trace = points.map(p => `${(180 + (p[0] - (minX + maxX) / 2) * aspect * scale).toFixed(1)},${(95 - (p[1] - (minY + maxY) / 2) * scale).toFixed(1)}`).join(' ');
  root.replaceChildren();
  const modal = root;
  modal.innerHTML = `${lockupSvg('Waybi', 'journey-lockup', 210)}<h2 id="journeySummaryTitle">${escapeHtml(title)}</h2>
    <p>${escapeHtml(destinationName)}</p><div class="journey-stats"><div><strong>${formatDistance(journeyDistance, language)}</strong><span>${t(language, 'journeyTravelled')}</span></div>
    <div><strong>${escapeHtml(t(language, 'durationMinutes', { minutes }))}</strong><span>${t(language, 'journeyTime')}</span></div></div>
    <svg class="journey-trace" viewBox="0 0 360 190" role="img" aria-label="${escapeHtml(t(language, 'journeyOverview'))}"><rect width="360" height="190" rx="20" fill="#eaf5cf"/>
    <polyline points="${trace}" fill="none" stroke="white" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>
    <polyline points="${trace}" fill="none" stroke="#486b29" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/></svg>
    <p>${escapeHtml(t(language, 'journeyTagline'))}</p>`;
  const done = document.createElement('button'); done.type = 'button'; done.className = 'primary-button'; done.textContent = t(language, 'keepExploring');
  done.onclick = () => closeDialog(root);
  modal.append(done);
  // Focus returns to the Start button (the trip's own control) when it closes.
  openDialog(root, $('driveButton'));
  done.focus();
}

($('keepScreenAwakeToggle') as HTMLInputElement).checked = keepScreenAwake;
$('keepScreenAwakeToggle').onchange = () => {
  keepScreenAwake = ($('keepScreenAwakeToggle') as HTMLInputElement).checked;
  localStorage.setItem('kiwi-keep-screen-awake', keepScreenAwake ? 'on' : 'off');
  void updateWakeLock();
};
