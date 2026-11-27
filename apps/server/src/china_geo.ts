import type { LonLat } from './types.ts';

/**
 * Mainland China geometry for provider selection and the GCJ-02 datum.
 *
 * Waybi's base map and device GPS are WGS-84. Mainland Chinese map providers
 * (Amap/AutoNavi) publish coordinates in GCJ-02, which is offset from WGS-84
 * by roughly 100–700 m. Every coordinate sent to Amap is converted with
 * wgs84ToGcj02, and every coordinate received is converted back with the
 * iterative gcj02ToWgs84 before it reaches the map, a route line or GPS
 * matching.
 *
 * The polygon is deliberately simplified (about 260 vertices) and follows the
 * coastline a few kilometres offshore. It separates mainland China from its
 * land neighbours and excludes Hong Kong, Macau, Taiwan, Penghu, Kinmen,
 * Matsu and Wuqiu, which keep Waybi's existing global stack. Precision near
 * remote land borders is a few kilometres; near the Shenzhen/Hong Kong,
 * Zhuhai/Macau and Xiamen/Kinmen boundaries it is a few hundred metres.
 *
 * The same vertices are mirrored in apps/mobile/lib/domain/china_region.dart;
 * tests/china_geo.test.ts fails if the two copies diverge.
 */

// BEGIN MAINLAND_CHINA_POLYGON (lon, lat pairs; mirrored in Dart)
export const MAINLAND_CHINA_OUTLINE: readonly LonLat[] = [
  // Yellow Sea, East China Sea and South China Sea coast, north to south.
  [124.10, 39.78], [123.55, 39.30], [123.05, 38.85], [123.10, 37.45],
  [122.90, 36.75], [121.10, 35.60], [121.20, 34.30], [121.90, 33.00],
  [122.35, 32.05], [122.40, 31.40], [123.05, 30.85], [122.95, 30.05],
  [122.55, 29.20], [122.40, 28.55], [121.55, 27.40], [120.95, 26.85],
  [120.20, 25.75], [119.85, 25.10], [118.75, 24.40], [118.30, 24.20],
  [117.75, 23.55], [117.20, 23.15], [116.50, 22.70], [115.60, 22.55],
  [114.95, 22.40], [114.60, 22.05], [113.95, 21.75], [113.10, 21.60],
  [112.55, 21.45], [111.80, 21.30], [110.95, 20.85],
  // Around Hainan.
  [111.35, 20.05], [111.15, 19.10], [110.70, 18.40], [109.75, 17.95],
  [108.55, 18.35], [108.40, 19.20], [108.95, 20.00],
  // Gulf of Tonkin to the Beilun River (Dongxing / Mong Cai).
  [108.80, 20.75], [108.20, 21.25], [108.06, 21.52], [107.99, 21.535],
  // Vietnam.
  [107.90, 21.56], [107.60, 21.62], [107.35, 21.64], [107.05, 21.85],
  [106.70, 21.99], [106.65, 22.30], [106.52, 22.47], [106.72, 22.85],
  [106.30, 22.86], [105.90, 23.10], [105.50, 23.20], [105.32, 23.40],
  [105.00, 23.25], [104.80, 22.95], [104.35, 22.72], [104.02, 22.55], [103.97, 22.495], [103.93, 22.50],
  [103.65, 22.78], [103.40, 22.70], [103.15, 22.58], [102.90, 22.50],
  [102.65, 22.65], [102.40, 22.60], [102.14, 22.40],
  // Laos.
  [101.80, 22.45], [101.55, 22.20], [101.75, 21.75], [101.78, 21.20],
  [101.25, 21.15], [101.15, 21.15],
  // Myanmar.
  [101.10, 21.60], [100.65, 21.45], [100.20, 21.45], [100.05, 21.68],
  [99.95, 22.05], [99.20, 22.12], [99.05, 22.95], [98.90, 23.20],
  [98.82, 23.75], [98.50, 24.08], [98.20, 24.10], [97.88, 24.00],
  [97.55, 23.95], [97.53, 24.45], [97.70, 24.85], [97.75, 25.25],
  [98.15, 25.60], [98.55, 26.10], [98.70, 26.75], [98.45, 27.60],
  [98.30, 27.95], [98.10, 28.15], [97.35, 28.25],
  // India (eastern sector), Bhutan, Sikkim and Nepal.
  [97.00, 28.55], [96.55, 28.85], [96.15, 29.40], [95.40, 29.15],
  [94.60, 29.25], [94.00, 28.95], [93.30, 28.65], [92.65, 28.10],
  [91.95, 27.85], [91.65, 27.92], [91.25, 28.05], [90.55, 28.25],
  [90.00, 28.32], [89.55, 28.18], [89.20, 27.80], [89.00, 27.30],
  [88.82, 27.36], [88.80, 27.95], [88.60, 28.10], [88.15, 27.90],
  [87.95, 27.90], [87.15, 27.88], [86.90, 28.00], [86.30, 28.05],
  [86.05, 27.95], [85.95, 27.97], [85.70, 28.30], [85.37, 28.28],
  [85.15, 28.60], [84.45, 28.75], [84.10, 29.25], [83.55, 29.20],
  [82.95, 29.75], [81.85, 30.05], [81.30, 30.20], [80.95, 30.23],
  // India (western sector), Pakistan, Afghanistan and Tajikistan.
  [80.20, 30.80], [79.40, 31.00], [79.05, 31.40], [78.75, 31.85],
  [78.75, 32.55], [79.35, 32.55], [79.55, 32.75], [78.75, 33.35],
  [78.85, 33.55], [79.05, 34.00], [78.30, 34.65], [77.95, 35.30],
  [77.83, 35.51], [77.00, 35.95], [76.51, 35.88], [75.90, 36.35],
  [75.42, 36.85], [74.92, 37.02], [74.85, 37.30], [74.95, 38.20],
  [74.85, 38.50], [74.40, 38.75], [73.85, 39.40],
  // Kyrgyzstan and Kazakhstan.
  [73.95, 39.72], [74.85, 40.50], [75.40, 40.52], [76.20, 40.40],
  [76.90, 41.00], [78.10, 41.25], [79.25, 41.90], [80.20, 42.20],
  [80.25, 42.80], [80.35, 44.20], [80.75, 45.05], [81.80, 45.20],
  [82.55, 45.22], [82.30, 45.55], [82.70, 46.55], [83.10, 47.20],
  [85.50, 47.05], [85.70, 48.00], [86.55, 48.55], [86.85, 49.10],
  // Russia (Altai) and Mongolia.
  [87.35, 49.17], [87.85, 49.15], [88.25, 48.50], [89.00, 47.95],
  [90.10, 47.70], [90.45, 46.95], [90.90, 45.95], [91.00, 45.35],
  [93.50, 44.95], [95.35, 44.25], [96.40, 42.75], [97.20, 42.80],
  [100.80, 42.65], [101.80, 42.50], [103.40, 41.90], [104.50, 41.65],
  [105.00, 41.60], [106.80, 42.30], [108.50, 42.45], [110.40, 42.75],
  [111.94, 43.69], [113.60, 44.75], [116.00, 45.60], [116.60, 46.30],
  [117.40, 46.55], [118.55, 46.75], [119.70, 46.60], [119.95, 46.90],
  [119.00, 47.55], [117.75, 47.95], [116.85, 47.88], [115.55, 47.90],
  [115.60, 48.15], [116.70, 49.85],
  // Russia: Argun, Amur and Ussuri rivers.
  [117.40, 49.66], [117.95, 49.62], [119.15, 50.25], [119.40, 50.75],
  [119.95, 51.55], [120.65, 52.45], [121.65, 53.15], [122.40, 53.50],
  [123.25, 53.57], [124.50, 53.25], [125.50, 53.05], [126.15, 52.75],
  [126.55, 52.05], [126.80, 51.55], [127.25, 50.80], [127.52, 50.26],
  [128.85, 49.50], [129.70, 49.25], [130.65, 48.85], [130.95, 47.70],
  [132.55, 47.75], [134.20, 48.40], [134.75, 48.35], [134.65, 47.70],
  [134.20, 47.20], [134.05, 46.65], [133.85, 46.20], [133.50, 45.85],
  [133.10, 45.25], [132.85, 45.05], [131.95, 45.20], [131.10, 44.85],
  [131.25, 44.40], [131.30, 44.10], [131.10, 43.40], [130.95, 42.90],
  [130.65, 42.45],
  // North Korea: Tumen and Yalu rivers.
  [130.30, 42.65], [129.85, 42.95], [129.70, 42.42], [128.95, 42.05],
  [128.10, 42.00], [128.20, 41.43], [127.40, 41.48], [126.55, 41.60],
  [126.20, 41.10], [125.30, 40.65], [124.40, 40.11],
];

/** Areas inside the coastal outline that are not mainland China. */
export const MAINLAND_CHINA_EXCLUSIONS: Readonly<Record<string, readonly LonLat[]>> = {
  hongKong: [
    [113.825, 22.15], [113.835, 22.37], [114.00, 22.50], [114.03, 22.508],
    [114.06, 22.512], [114.085, 22.521], [114.105, 22.531], [114.125, 22.537],
    [114.15, 22.545], [114.17, 22.557], [114.20, 22.556], [114.225, 22.545],
    [114.26, 22.553], [114.33, 22.556], [114.40, 22.555], [114.44, 22.565],
    [114.455, 22.50], [114.45, 22.13], [113.95, 22.13], [113.90, 22.14],
  ],
  macau: [
    [113.531, 22.18], [113.531, 22.205], [113.54, 22.213], [113.548, 22.216],
    [113.556, 22.214], [113.565, 22.20], [113.575, 22.185], [113.61, 22.17],
    [113.61, 22.105], [113.556, 22.105], [113.556, 22.165],
  ],
  kinmen: [
    [118.12, 24.35], [118.52, 24.35], [118.52, 24.52], [118.43, 24.545],
    [118.35, 24.535], [118.28, 24.505], [118.215, 24.47], [118.205, 24.43],
    [118.17, 24.415], [118.12, 24.40],
  ],
  matsuNanganBeigan: [
    [119.89, 26.12], [120.06, 26.12], [120.06, 26.26], [119.96, 26.26],
    [119.89, 26.19],
  ],
  matsuJuguang: [[119.90, 25.92], [120.02, 25.92], [120.02, 26.00], [119.90, 26.00]],
  matsuDongyin: [[120.45, 26.33], [120.55, 26.33], [120.55, 26.40], [120.45, 26.40]],
  wuqiu: [[119.43, 24.96], [119.47, 24.96], [119.47, 25.00], [119.43, 25.00]],
};
// END MAINLAND_CHINA_POLYGON

const BOUNDS = (() => {
  const lons = MAINLAND_CHINA_OUTLINE.map(point => point[0]);
  const lats = MAINLAND_CHINA_OUTLINE.map(point => point[1]);
  return { west: Math.min(...lons), east: Math.max(...lons), south: Math.min(...lats), north: Math.max(...lats) };
})();

/** Even-odd ray casting; the ring may be open or closed. */
export function pointInRing(lon: number, lat: number, ring: readonly LonLat[]): boolean {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    if ((yi > lat) !== (yj > lat) && lon < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

/**
 * True for a WGS-84 coordinate in mainland China (including Hainan and the
 * coastal islands administered from the mainland). Hong Kong, Macau, Taiwan,
 * Penghu, Kinmen and Matsu return false.
 */
export function isMainlandChina(lon: number, lat: number): boolean {
  if (!Number.isFinite(lon) || !Number.isFinite(lat)) return false;
  if (lon < BOUNDS.west || lon > BOUNDS.east || lat < BOUNDS.south || lat > BOUNDS.north) return false;
  if (!pointInRing(lon, lat, MAINLAND_CHINA_OUTLINE)) return false;
  return !Object.values(MAINLAND_CHINA_EXCLUSIONS).some(ring => pointInRing(lon, lat, ring));
}

export function allInMainlandChina(points: readonly LonLat[]): boolean {
  return points.length > 0 && points.every(([lon, lat]) => isMainlandChina(lon, lat));
}

// GCJ-02 (国测局坐标) uses the Krasovsky 1940 ellipsoid parameters.
const A = 6378245.0;
const EE = 0.00669342162296594323;

/** The datum shift is only defined over the published China extent. */
export function outsideGcjExtent(lon: number, lat: number): boolean {
  return !(lon > 72.004 && lon < 137.8347 && lat > 0.8293 && lat < 55.8271);
}

function shiftLat(x: number, y: number): number {
  let value = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * Math.sqrt(Math.abs(x));
  value += ((20 * Math.sin(6 * x * Math.PI) + 20 * Math.sin(2 * x * Math.PI)) * 2) / 3;
  value += ((20 * Math.sin(y * Math.PI) + 40 * Math.sin((y / 3) * Math.PI)) * 2) / 3;
  value += ((160 * Math.sin((y / 12) * Math.PI) + 320 * Math.sin((y * Math.PI) / 30)) * 2) / 3;
  return value;
}

function shiftLon(x: number, y: number): number {
  let value = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * Math.sqrt(Math.abs(x));
  value += ((20 * Math.sin(6 * x * Math.PI) + 20 * Math.sin(2 * x * Math.PI)) * 2) / 3;
  value += ((20 * Math.sin(x * Math.PI) + 40 * Math.sin((x / 3) * Math.PI)) * 2) / 3;
  value += ((150 * Math.sin((x / 12) * Math.PI) + 300 * Math.sin((x / 30) * Math.PI)) * 2) / 3;
  return value;
}

/** Standard forward transform. Outside the China extent it is the identity. */
export function wgs84ToGcj02(lon: number, lat: number): LonLat {
  if (outsideGcjExtent(lon, lat)) return [lon, lat];
  let dLat = shiftLat(lon - 105, lat - 35);
  let dLon = shiftLon(lon - 105, lat - 35);
  const radLat = (lat / 180) * Math.PI;
  let magic = Math.sin(radLat);
  magic = 1 - EE * magic * magic;
  const sqrtMagic = Math.sqrt(magic);
  dLat = (dLat * 180) / (((A * (1 - EE)) / (magic * sqrtMagic)) * Math.PI);
  dLon = (dLon * 180) / ((A / sqrtMagic) * Math.cos(radLat) * Math.PI);
  return [lon + dLon, lat + dLat];
}

/**
 * Iterative inverse of wgs84ToGcj02. The common one-step approximation is
 * wrong by up to a couple of metres; a few fixed-point iterations bring the
 * round trip below a millimetre, well under GPS noise.
 */
export function gcj02ToWgs84(lon: number, lat: number): LonLat {
  if (outsideGcjExtent(lon, lat)) return [lon, lat];
  let wgsLon = lon;
  let wgsLat = lat;
  for (let i = 0; i < 30; i++) {
    const [gcjLon, gcjLat] = wgs84ToGcj02(wgsLon, wgsLat);
    const errorLon = gcjLon - lon;
    const errorLat = gcjLat - lat;
    wgsLon -= errorLon;
    wgsLat -= errorLat;
    if (Math.abs(errorLon) < 1e-10 && Math.abs(errorLat) < 1e-10) break;
  }
  return [wgsLon, wgsLat];
}

/** `lng,lat` with Amap's six-decimal limit, converted to GCJ-02. */
export function gcjParameter([lon, lat]: LonLat): string {
  const [x, y] = wgs84ToGcj02(lon, lat);
  return `${x.toFixed(6)},${y.toFixed(6)}`;
}

/** Parse one Amap `lng,lat` string (GCJ-02) to a WGS-84 coordinate. */
export function parseGcjPoint(value: unknown): LonLat | null {
  if (typeof value !== 'string') return null;
  const [rawLon, rawLat] = value.split(',');
  const lon = Number(rawLon);
  const lat = Number(rawLat);
  if (!rawLon || !rawLat || !Number.isFinite(lon) || !Number.isFinite(lat) ||
      lon < -180 || lon > 180 || lat < -90 || lat > 90) return null;
  return gcj02ToWgs84(lon, lat);
}

/** Parse an Amap polyline (`lng,lat;lng,lat`) to WGS-84 coordinates. */
export function parseGcjPolyline(value: unknown): LonLat[] {
  if (typeof value !== 'string' || !value) return [];
  const points: LonLat[] = [];
  for (const pair of value.split(';')) {
    const point = parseGcjPoint(pair);
    if (point) points.push(point);
  }
  return points;
}
