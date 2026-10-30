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

export type PoiReview = { author: string; authorPhoto: string | null; rating: number | null; text: string; relativeTime: string; sourceUrl: string | null };
export type PoiSelection = {
  placeId: string; name: string; address: string; coordinate: Coordinate; primaryType: string;
  rating: number | null; userRatingCount: number | null; businessStatus: string | null; priceLevel: string | null;
  phone: string; websiteURI: string; sourceUrl: string; editorialSummary: string; openingHours: string[];
  photos: { url: string; attribution: string }[]; reviews: PoiReview[];
};
type InitOptions = { language: 'zh' | 'en'; onDragStart: () => void; onMapClick: () => void; onPoiSelected: (place: PoiSelection) => void };
type TrafficRoute = { route: Route; trafficIntervals: TrafficInterval[] };
const empty = (): GeoJSON.FeatureCollection => ({ type: 'FeatureCollection', features: [] });

export class WaybiMapAdapter {
  private map?: maplibregl.Map;
  private language: 'zh' | 'en' = 'en';
  private hosted = true;
  private hostedFailed = false;
  private cameraMarkers: maplibregl.Marker[] = [];
  private parkingMarkers: maplibregl.Marker[] = [];
  private positionMarker?: maplibregl.Marker;
  private destinationMarker?: maplibregl.Marker;
  private pendingPosition?: { coordinate: Coordinate; heading: number | null };
  private pendingCameras?: { cameras: Camera[]; onRoute: Set<string>; language: 'zh' | 'en' };
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
    map.addControl(new maplibregl.AttributionControl({ compact: true }), 'bottom-right');
    new ResizeObserver(() => map.resize()).observe(document.getElementById('map')!);
    map.on('dragstart', options.onDragStart);
    map.on('rotate', () => this.paintPosition());
    map.on('moveend', () => {
      const center = map.getCenter();
      const hosted = !this.hostedFailed && inNewZealand([center.lng, center.lat]);
      if (hosted !== this.hosted) {
        this.hosted = hosted;
        map.setStyle(waybiStyle(this.language, hosted));
      }
    });
    map.on('style.load', () => { this.paintRoutes(); this.paintRadar(); });
    map.on('error', (event) => {
      if ('sourceId' in event && event.sourceId === 'openmaptiles' && this.hosted) {
        this.hostedFailed = true;
        this.hosted = false;
        map.setStyle(waybiStyle(this.language, false));
      }
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
    if (this.pendingCameras) this.renderCameras(this.pendingCameras.cameras, this.pendingCameras.onRoute, this.pendingCameras.language);
    if (this.pendingRoute) this.renderRoute(this.pendingRoute.route, this.pendingRoute.destination, this.pendingRoute.navigating);
    this.paintRoutes();
  }

  renderCameras(cameras: Camera[], onRoute: Set<string>, language: 'zh' | 'en') {
    this.pendingCameras = { cameras, onRoute, language };
    if (!this.map) return;
    this.cameraMarkers.forEach(marker => marker.remove());
    this.cameraMarkers = cameras.map(camera => {
      const button = document.createElement('button');
      button.type = 'button'; button.className = `camera-pin ${camera.type.toLowerCase().includes('red light') ? 'red' : ''} ${onRoute.has(camera.id) ? 'route' : ''}`;
      button.textContent = '◉'; button.setAttribute('aria-label', camera.location);
      const popup = document.createElement('div');
      for (const text of [cameraLabel(camera.type, language), camera.location, `${camera.suburb} · ${camera.region}`, `NZTA · ${camera.updatedAt}`]) {
        const line = document.createElement('div'); line.textContent = text; popup.append(line);
      }
      return new maplibregl.Marker({ element: button }).setLngLat([camera.longitude, camera.latitude])
        .setPopup(new maplibregl.Popup({ offset: 20 }).setDOMContent(popup)).addTo(this.map!);
    });
  }

  async searchParking(center: Coordinate): Promise<ParkingPlace[]> {
    const params = new URLSearchParams({ q: 'parking', near: center.join(','), provider: 'independent', lang: this.language });
    const response = await fetch(`/api/search?${params}`, { signal: AbortSignal.timeout(10000) });
    if (!response.ok) throw new Error('Parking search is unavailable');
    const places = await response.json() as { id: string; label: string; name?: string; latitude: number; longitude: number }[];
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
      button.className = `parking-pin${place.id === selectedId ? ' selected' : ''}`;
      button.textContent = 'P'; button.setAttribute('aria-label', place.name);
      button.onclick = (event) => { event.stopPropagation(); onSelect(place); };
      return new maplibregl.Marker({ element: button }).setLngLat(place.coordinate).addTo(this.map!);
    });
  }

  setPosition(coordinate: Coordinate, heading: number | null) { this.pendingPosition = { coordinate, heading }; this.paintPosition(); this.paintRadar(); }
  private paintPosition() {
    if (!this.map || !this.pendingPosition) return;
    const element = document.createElement('span'); element.className = 'position-pin';
    if (this.pendingPosition.heading !== null) {
      const arrow = document.createElement('span'); arrow.className = 'position-heading';
      arrow.style.transform = `rotate(${this.pendingPosition.heading - this.map.getBearing()}deg)`; element.append(arrow);
    }
    this.positionMarker?.remove();
    this.positionMarker = new maplibregl.Marker({ element }).setLngLat(this.pendingPosition.coordinate).addTo(this.map);
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
    this.destinationMarker?.remove();
    const element = document.createElement('span'); element.className = 'camera-pin route destination-pin'; element.textContent = '◆';
    this.destinationMarker = new maplibregl.Marker({ element }).setLngLat(destination).addTo(this.map);
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
