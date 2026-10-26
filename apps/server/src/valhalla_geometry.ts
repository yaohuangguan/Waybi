import type { LonLat, ProviderPayload } from './types.ts';

/** Valhalla/OSRM polyline6 uses latitude first and 1e6 precision. The Worker
 * returns its existing longitude-first GeoJSON contract to all clients. */
export function decodePolyline6(encoded: string): LonLat[] {
  const coordinates: LonLat[] = [];
  let index = 0, lat = 0, lon = 0;
  const delta = () => {
    let result = 0, shift = 0, byte: number;
    do {
      if (index >= encoded.length || shift > 30) throw new Error('Invalid Valhalla polyline6');
      byte = encoded.charCodeAt(index++) - 63;
      if (byte < 0 || byte > 63) throw new Error('Invalid Valhalla polyline6');
      result |= (byte & 31) << shift;
      shift += 5;
    } while (byte >= 32);
    return result & 1 ? ~(result >>> 1) : result >>> 1;
  };
  while (index < encoded.length) {
    lat += delta(); lon += delta();
    if (Math.abs(lat) > 90e6 || Math.abs(lon) > 180e6) throw new Error('Invalid Valhalla coordinate');
    coordinates.push([lon / 1e6, lat / 1e6]);
  }
  if (coordinates.length < 2) throw new Error('Incomplete Valhalla route geometry');
  return coordinates;
}

export function restoreValhallaGeometry(payload: ProviderPayload) {
  for (const route of payload.routes || []) {
    if (typeof route.geometry === 'string') {
      route.geometry = { type: 'LineString', coordinates: decodePolyline6(route.geometry) };
    }
  }
  return payload;
}
