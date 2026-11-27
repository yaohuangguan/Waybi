import * as maplibregl from 'maplibre-gl';
import type { GeoJSONSource, StyleSpecification } from 'maplibre-gl';
import type * as GeoJSON from 'geojson';
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url';
import { Protocol } from 'pmtiles';
import 'maplibre-gl/dist/maplibre-gl.css';
import baseStyle from '../../mobile/assets/maps/positron_base.json?raw';
import { cameraLabel, distanceMeters, type Camera, type Coordinate, type Route } from '@waybi/core';
import type { ParkingPlace } from './parking';
import type { TrafficInterval } from './route-planner';
import { apiFetch } from './api';

// Share the native app's NZ archive, global fallback, style and legal credits.
export const NZ_TILES = 'pmtiles://https://maps.waybi.co/regions/nz.pmtiles';
export const GLOBAL_TILES = 'https://tiles.openfreemap.org/planet';
const protocol = new Protocol();
maplibregl.addProtocol('pmtiles', protocol.tile);
maplibregl.setWorkerUrl(workerUrl);

export function inNewZealand([lon, lat]: Coordinate) {
  return lon >= 166 && lon <= 179 && lat >= -48 && lat <= -34;
}

export function waybiStyle(language: 'zh' | 'en', hosted: boolean): StyleSpecification {
  const style = JSON.parse(baseStyle);
  style.sources.openmaptiles.url = hosted ? NZ_TILES : GLOBAL_TILES;
  style.sources.openmaptiles.attribution = '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> · <a href="/map-licenses.txt">Map credits</a>';
  for (const layer of style.layers) {
    const id = layer.id as string;
    if (layer.type === 'background') layer.paint['background-color'] = '#f6f7f8';
    if (layer.type === 'fill') layer.paint['fill-color'] = id.includes('water') ? '#e5eef3'
      : id.includes('park') || id.includes('wood') ? '#cfe6bf' : id.includes('building') ? '#e9ebed' : '#f1f2f3';
    if (layer.type === 'symbol' && layer.layout?.['text-field'] && !id.includes('shield')) {
      layer.layout['text-field'] = ['coalesce', ...(language === 'zh' ? [['get', 'name:zh']] : []), ['get', 'name'], ['get', 'name:en'], ['get', 'name:latin']];
      layer.layout['text-font'] = ['Noto Sans Regular'];
      layer.paint = { ...layer.paint, 'text-color': '#59636b', 'text-halo-color': '#f6f7f8', 'text-halo-width': 1.2 };
    }
  }
  return style as StyleSpecification;
}

/**
 * Decides when the hosted NZ archive has really failed. If it has never
 * served a tile in this session (archive unreachable), the first error falls
 * back at once; once it has worked, a single flaky tile no longer switches
 * the whole session: it takes several errors in a short window. Either way
 * the hosted archive is tried again after a cool-down.
 */
export class TileFailover {
  private errors: number[] = [];
  private blockedUntil = 0;
  private healthy = false;
  constructor(private readonly threshold = 4, private readonly windowMs = 30_000, private readonly retryAfterMs = 5 * 60_000) {}
  /** Records a hosted-tile error; returns true when the map should fall back now. */
  recordError(now = Date.now()) {
    if (this.blocked(now)) return false;
    this.errors = this.errors.filter((time) => now - time < this.windowMs);
    this.errors.push(now);
    if (this.healthy && this.errors.length < this.threshold) return false;
    this.errors = [];
    this.healthy = false;
    this.blockedUntil = now + this.retryAfterMs;
    return true;
  }
  /** While blocked, the global tiles are used even inside New Zealand. */
  blocked(now = Date.now()) { return now < this.blockedUntil; }
  /** A hosted tile loaded: from now on, tolerate isolated errors. */
  recordSuccess() { this.healthy = true; }
}

export type PoiReview = { author: string; authorPhoto: string | null; rating: number | null; text: string; relativeTime: string; sourceUrl: string | null };
export type PoiSelection = {
  placeId: string; name: string; address: string; coordinate: Coordinate; primaryType: string;
  rating: number | null; userRatingCount: number | null; businessStatus: string | null; priceLevel: string | null;
  phone: string; websiteURI: string; sourceUrl: string; editorialSummary: string; openingHours: string[];
  photos: { url: string; attribution: string }[]; reviews: PoiReview[];
};
type InitOptions = { language: 'zh' | 'en'; onDragStart: () => void; onMapClick: () => void; onPoiSelected: (place: PoiSelection) => void };
type TrafficRoute = { route: Route; trafficIntervals: TrafficInterval[] };
type CameraMarker = { marker: maplibregl.Marker; element: HTMLButtonElement; camera: Camera };
const empty = (): GeoJSON.FeatureCollection => ({ type: 'FeatureCollection', features: [] });
const OWN_PREFIX = 'waybi-';

/** Keeps Waybi's own route, traffic and heading layers across a style swap (language or tile source). */
export function keepOwnLayers(previous: StyleSpecification | undefined, next: StyleSpecification): StyleSpecification {
  if (!previous) return next;
  const sources = { ...next.sources };
  for (const [id, source] of Object.entries(previous.sources || {})) if (id.startsWith(OWN_PREFIX)) sources[id] = source;
  const layers = [...next.layers, ...(previous.layers || []).filter((layer) => layer.id.startsWith(OWN_PREFIX))];
  return { ...next, sources, layers };
}

export class WaybiMapAdapter {
  private map?: maplibregl.Map;
  private language: 'zh' | 'en' = 'en';
  private hosted = true;
  private readonly failover = new TileFailover();
  private cameraMarkers = new Map<string, CameraMarker>();
  private parkingMarkers: maplibregl.Marker[] = [];
  private positionMarker?: maplibregl.Marker;
  private positionElement?: HTMLElement;
  private destinationMarker?: maplibregl.Marker;
  private attribution?: maplibregl.AttributionControl;
  private attributionPosition?: 'bottom-left' | 'bottom-right';
  private pendingPosition?: { coordinate: Coordinate; heading: number | null };
  private pendingCameras?: { cameras: Camera[]; onRoute: Set<string> };
  private pendingRoute?: { route: Route; destination: Coordinate; navigating: boolean };
  private alternatives: TrafficRoute[] = [];
  private selectedIndex = 0;
  private onSelect?: (index: number) => void;
  private trafficEnabled = true;
  private radarHeading: number | null = null;

  async init(options: InitOptions) {
    this.language = options.language;
    this.map = new maplibregl.Map({
      container: 'map', style: waybiStyle(this.language, this.hosted),
      center: [174.7633, -36.8485], zoom: 12, attributionControl: false,
    });
    const map = this.map;
    this.placeAttribution();
    window.addEventListener('resize', () => this.placeAttribution());
    new ResizeObserver(() => map.resize()).observe(document.getElementById('map')!);
    map.on('dragstart', options.onDragStart);
    map.on('moveend', () => this.updateTileSource());
    // Waybi's layers survive a style swap through keepOwnLayers; repaint in
    // case a full reload happened (first load, or a source that cannot diff).
    map.on('style.load', () => { this.paintRoutes(); this.paintRadar(); });
    map.on('styledata', () => { if (map.isStyleLoaded() && !map.getLayer('waybi-route-line')) this.paintRoutes(); });
    map.on('sourcedata', (event) => {
      if (this.hosted && event.sourceId === 'openmaptiles' && (event as { tile?: unknown }).tile) this.failover.recordSuccess();
    });
    map.on('error', (event) => {
      if (!('sourceId' in event) || event.sourceId !== 'openmaptiles' || !this.hosted) return;
      if (this.failover.recordError()) this.setTileSource(false);
    });
    map.on('click', (event) => {
      const routeFeature = map.queryRenderedFeatures(event.point).find(feature => feature.layer.id === 'waybi-alternatives');
      if (routeFeature && this.onSelect) { this.onSelect(Number(routeFeature.properties.index)); return; }
      const feature = map.queryRenderedFeatures(event.point).find(item => item.sourceLayer === 'poi' && item.properties.name);
      if (!feature || document.body.dataset.mode === 'navigation') { options.onMapClick(); return; }
      const coordinate: Coordinate = feature.geometry.type === 'Point' ? feature.geometry.coordinates.slice(0, 2) as Coordinate : [event.lngLat.lng, event.lngLat.lat];
      const p = feature.properties;
      options.onPoiSelected({
        placeId: `osm:${p.osm_id || feature.id || coordinate.join(',')}`,
        name: String(this.language === 'zh' ? p['name:zh'] || p.name : p.name),
        address: '', coordinate, primaryType: String(p.class || 'OpenStreetMap'),
        rating: null, userRatingCount: null, businessStatus: null, priceLevel: null,
        phone: '', websiteURI: '', sourceUrl: `https://www.openstreetmap.org/?mlat=${coordinate[1]}&mlon=${coordinate[0]}#map=18/${coordinate[1]}/${coordinate[0]}`,
        editorialSummary: '', openingHours: [], photos: [], reviews: [],
      });
    });
    await new Promise<void>((resolve, reject) => {
      const timeout = window.setTimeout(() => reject(new Error('Map could not load. Check your connection and refresh.')), 20000);
      map.once('load', () => { window.clearTimeout(timeout); resolve(); });
    });
    this.paintPosition();
    if (this.pendingCameras) this.renderCameras(this.pendingCameras.cameras, this.pendingCameras.onRoute);
    if (this.pendingRoute) this.renderRoute(this.pendingRoute.route, this.pendingRoute.destination, this.pendingRoute.navigating);
    this.paintRoutes();
  }

  /** On phones the credits sit bottom-left, clear of the map buttons stacked on the right. */
  private placeAttribution() {
    if (!this.map) return;
    const position = window.innerWidth < 760 ? 'bottom-left' : 'bottom-right';
    if (position === this.attributionPosition) return;
    if (this.attribution) this.map.removeControl(this.attribution);
    this.attribution = new maplibregl.AttributionControl({ compact: true });
    this.map.addControl(this.attribution, position);
    this.attributionPosition = position;
  }

  private updateTileSource() {
    if (!this.map) return;
    const center = this.map.getCenter();
    const hosted = !this.failover.blocked() && inNewZealand([center.lng, center.lat]);
    if (hosted !== this.hosted) this.setTileSource(hosted);
  }

  private setTileSource(hosted: boolean) {
    this.hosted = hosted;
    this.applyStyle();
  }

  private applyStyle() {
    this.map?.setStyle(waybiStyle(this.language, this.hosted), { transformStyle: keepOwnLayers });
  }

  /** Switches map labels without reloading the page; markers, route and camera stay. */
  setLanguage(language: 'zh' | 'en') {
    if (language === this.language) return;
    this.language = language;
    if (this.map) this.applyStyle();
  }

  getCenter(): Coordinate | null {
    const center = this.map?.getCenter();
    return center ? [center.lng, center.lat] : null;
  }

  private cameraPopup(camera: Camera) {
    const popup = new maplibregl.Popup({ offset: 20 });
    // Built when opened so it always uses the current language.
    popup.on('open', () => {
      const content = document.createElement('div');
      content.className = 'camera-popup';
      for (const text of [cameraLabel(camera.type, this.language), camera.location, `${camera.suburb} · ${camera.region}`, `NZTA · ${camera.updatedAt}`]) {
        const line = document.createElement('div'); line.textContent = text; content.append(line);
      }
      popup.setDOMContent(content);
    });
    return popup;
  }

  /**
   * Updates camera markers in place: markers are only created for new
   * cameras and removed for missing ones; a route change only toggles a
   * class. Markers stay out of the Tab order (the sheet's camera list is the
   * keyboard route to them).
   */
  renderCameras(cameras: Camera[], onRoute: Set<string>) {
    this.pendingCameras = { cameras, onRoute };
    if (!this.map) return;
    const seen = new Set<string>();
    for (const camera of cameras) {
      seen.add(camera.id);
      let entry = this.cameraMarkers.get(camera.id);
      if (!entry) {
        const element = document.createElement('button');
        element.type = 'button';
        element.tabIndex = -1;
        element.textContent = '◉';
        element.setAttribute('aria-label', camera.location);
        const marker = new maplibregl.Marker({ element }).setLngLat([camera.longitude, camera.latitude])
          .setPopup(this.cameraPopup(camera)).addTo(this.map);
        entry = { marker, element, camera };
        this.cameraMarkers.set(camera.id, entry);
      } else if (entry.camera.latitude !== camera.latitude || entry.camera.longitude !== camera.longitude) {
        entry.marker.setLngLat([camera.longitude, camera.latitude]);
        entry.camera = camera;
      }
      const className = `camera-pin${camera.type.toLowerCase().includes('red light') ? ' red' : ''}${onRoute.has(camera.id) ? ' route' : ''}`;
      if (entry.element.className !== className) entry.element.className = className;
    }
    for (const [id, entry] of this.cameraMarkers) {
      if (seen.has(id)) continue;
      entry.marker.remove();
      this.cameraMarkers.delete(id);
    }
  }

  /** Keyboard alternative to clicking a marker: centre the camera and open its details. */
  showCamera(id: string) {
    const entry = this.cameraMarkers.get(id);
    if (!entry || !this.map) return false;
    this.map.easeTo({ center: [entry.camera.longitude, entry.camera.latitude], zoom: Math.max(this.map.getZoom(), 15), duration: 300 });
    if (!entry.marker.getPopup()?.isOpen()) entry.marker.togglePopup();
    return true;
  }

  async searchParking(center: Coordinate): Promise<ParkingPlace[]> {
    const params = new URLSearchParams({ q: 'parking', near: center.join(','), provider: 'independent', lang: this.language });
    // Shares the search rate-limit gate, so a 429 pauses this too.
    const places = await apiFetch<{ id: string; label: string; name?: string; latitude: number; longitude: number }[]>(`/api/search?${params}`, { signal: AbortSignal.timeout(10000) });
    return places.flatMap(place => {
      const coordinate: Coordinate = [place.longitude, place.latitude];
      const distance = distanceMeters(center, coordinate);
      if (!Number.isFinite(distance) || distance > 1500 || !/parking|car park|停车/i.test(place.label)) return [];
      return [{ id: String(place.id), source: 'independent' as const, name: place.name || place.label.split(',')[0]!, address: place.label,
        coordinate, distanceMeters: distance, sourceUrl: '', totalSpaces: null, mobilitySpaces: null, clearanceMeters: null }];
    }).slice(0, 8);
  }

  renderParking(places: ParkingPlace[], selectedId: string | null, onSelect: (place: ParkingPlace) => void) {
    this.parkingMarkers.forEach(marker => marker.remove()); this.parkingMarkers = [];
    if (!this.map) return;
    this.parkingMarkers = places.map(place => {
      const button = document.createElement('button'); button.type = 'button';
      // The parking list in the sheet is the keyboard path; pins stay out of the Tab order.
      button.tabIndex = -1;
      button.className = `parking-pin${place.id === selectedId ? ' selected' : ''}`;
      button.textContent = 'P'; button.setAttribute('aria-label', place.name);
      button.onclick = (event) => { event.stopPropagation(); onSelect(place); };
      return new maplibregl.Marker({ element: button }).setLngLat(place.coordinate).addTo(this.map!);
    });
  }

  setPosition(coordinate: Coordinate, heading: number | null) { this.pendingPosition = { coordinate, heading }; this.paintPosition(); this.paintRadar(); }

  /** The position marker is created once and then moved and rotated; MapLibre compensates map bearing itself. */
  private paintPosition() {
    if (!this.map || !this.pendingPosition) return;
    const { coordinate, heading } = this.pendingPosition;
    if (!this.positionMarker) {
      const element = document.createElement('span');
      element.className = 'position-pin';
      element.setAttribute('aria-hidden', 'true');
      const arrow = document.createElement('span'); arrow.className = 'position-heading';
      element.append(arrow);
      this.positionElement = element;
      this.positionMarker = new maplibregl.Marker({ element, rotationAlignment: 'map', pitchAlignment: 'viewport' })
        .setLngLat(coordinate).addTo(this.map);
    } else this.positionMarker.setLngLat(coordinate);
    this.positionElement?.classList.toggle('has-heading', heading !== null);
    this.positionMarker.setRotation(heading ?? 0);
  }

  setRadarHeading(heading: number | null) { this.radarHeading = heading; this.paintRadar(); }
  private paintRadar() {
    if (!this.map?.isStyleLoaded()) return;
    const data = empty();
    if (this.pendingPosition && this.radarHeading !== null) {
      const origin = this.pendingPosition.coordinate;
      const ring: Coordinate[] = [origin];
      for (let offset = -34; offset <= 34; offset += 4) {
        const angle = (this.radarHeading + offset) * Math.PI / 180;
        ring.push([origin[0] + Math.sin(angle) * 500 / (111320 * Math.cos(origin[1] * Math.PI / 180)), origin[1] + Math.cos(angle) * 500 / 111320]);
      }
      ring.push(origin);
      data.features.push({ type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [ring] } });
    }
    this.source('waybi-heading', data);
    if (!this.map.getLayer('waybi-heading')) this.map.addLayer({ id: 'waybi-heading', type: 'fill', source: 'waybi-heading', paint: { 'fill-color': '#27a2a2', 'fill-opacity': 0.16 } });
  }
  setFollowHeading(heading: number | null) { if (heading !== null) this.map?.setBearing(heading); }
  setTrafficEnabled(enabled: boolean) { this.trafficEnabled = enabled; this.paintRoutes(); }
  rotateBy(degrees: number) { if (!this.map) return false; this.map.setBearing(this.map.getBearing() + degrees); return true; }

  renderTrafficRoutes(routes: TrafficRoute[], selectedIndex = 0, onSelect?: (index: number) => void) {
    this.alternatives = routes; this.selectedIndex = selectedIndex; this.onSelect = onSelect; this.paintRoutes();
  }
  clearTrafficRoutes() { this.alternatives = []; this.paintRoutes(); }
  private source(id: string, data: GeoJSON.FeatureCollection) {
    if (!this.map) return;
    const source = this.map.getSource(id) as GeoJSONSource | undefined;
    if (source) source.setData(data); else this.map.addSource(id, { type: 'geojson', data });
  }
  private paintRoutes() {
    const map = this.map;
    if (!map?.isStyleLoaded()) return;
    const alternatives = empty();
    this.alternatives.forEach(({ route, trafficIntervals }, index) => {
      const intervals = this.trafficEnabled && trafficIntervals.length ? trafficIntervals : [{ startPolylinePointIndex: 0, endPolylinePointIndex: route.coordinates.length - 1, speed: 'unknown' }];
      for (const interval of intervals) {
        const coordinates = route.coordinates.slice(interval.startPolylinePointIndex, interval.endPolylinePointIndex + 1);
        if (coordinates.length < 2) continue;
        alternatives.features.push({ type: 'Feature', properties: { index, selected: index === this.selectedIndex,
          color: interval.speed === 'trafficJam' ? '#d74738' : interval.speed === 'slow' ? '#d99520' : '#486b29' }, geometry: { type: 'LineString', coordinates } });
      }
    });
    this.source('waybi-alternatives', alternatives);
    const routeData = empty();
    if (this.pendingRoute) routeData.features.push({ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: this.pendingRoute.route.coordinates } });
    this.source('waybi-route', routeData);
    if (!map.getLayer('waybi-route-outline')) map.addLayer({ id: 'waybi-route-outline', type: 'line', source: 'waybi-route', paint: { 'line-color': '#ffffff', 'line-width': 11 }, layout: { 'line-cap': 'round', 'line-join': 'round' } });
    if (!map.getLayer('waybi-route-line')) map.addLayer({ id: 'waybi-route-line', type: 'line', source: 'waybi-route', paint: { 'line-color': '#486b29', 'line-width': 6 }, layout: { 'line-cap': 'round', 'line-join': 'round' } });
    if (!map.getLayer('waybi-alternatives')) map.addLayer({ id: 'waybi-alternatives', type: 'line', source: 'waybi-alternatives', paint: { 'line-color': ['get', 'color'], 'line-width': ['case', ['get', 'selected'], 6, 5], 'line-opacity': ['case', ['get', 'selected'], 1, 0.45] }, layout: { 'line-cap': 'round', 'line-join': 'round' } });
  }
  renderRoute(route: Route, destination: Coordinate, navigating: boolean) {
    this.pendingRoute = { route, destination, navigating }; this.paintRoutes();
    if (!this.map) return;
    if (!this.destinationMarker) {
      const element = document.createElement('span'); element.className = 'camera-pin route destination-pin'; element.textContent = '◆';
      element.setAttribute('aria-hidden', 'true');
      this.destinationMarker = new maplibregl.Marker({ element }).setLngLat(destination).addTo(this.map);
    } else this.destinationMarker.setLngLat(destination).addTo(this.map);
    if (!navigating) this.fitRoute(route);
  }
  clearRoute() { this.pendingRoute = undefined; this.alternatives = []; this.destinationMarker?.remove(); this.paintRoutes(); }
  setView(coordinate: Coordinate, zoom: number) { this.map?.jumpTo({ center: coordinate, zoom }); }
  panTo(coordinate: Coordinate) { this.map?.easeTo({ center: coordinate, duration: 250 }); }
  focusNavigation(coordinate: Coordinate, zoom = 17) {
    if (!this.map) return;
    const height = this.map.getContainer().clientHeight;
    this.map.easeTo({ center: this.pendingPosition?.coordinate || coordinate, zoom, pitch: 45,
      offset: [window.innerWidth >= 760 ? 220 : 0, height * .2], duration: 0 });
  }
  fitRoute(route: Route) {
    if (!this.map || route.coordinates.length < 2) return;
    const bounds = new maplibregl.LngLatBounds(); route.coordinates.forEach(point => bounds.extend(point));
    const desktop = window.innerWidth >= 760;
    const top = document.getElementById('searchPanel')?.getBoundingClientRect().bottom || 0;
    const height = this.map.getContainer().clientHeight;
    this.map.fitBounds(bounds, { padding: desktop ? { top: 45, right: 50, bottom: 45, left: Math.min(500, window.innerWidth * .44) } : { top: Math.min(top + 18, height * .35), right: 24, bottom: 28, left: 24 }, maxZoom: 17, pitch: 0, bearing: 0, duration: 300 });
  }
}
