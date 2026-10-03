export function validCoordinate(latitude, longitude) {
  return Number.isFinite(latitude) && Number.isFinite(longitude) &&
    latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
}

export function validNzCoordinate(latitude, longitude) {
  return validCoordinate(latitude, longitude) &&
    longitude > 166 && longitude < 179 && latitude > -48 && latitude < -34;
}

export function parseLonLat(value) {
  const match = /^(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$/.exec(value || '');
  if (!match) return null;
  const longitude = Number(match[1]);
  const latitude = Number(match[2]);
  return validCoordinate(latitude, longitude) ? [longitude, latitude] : null;
}

export function parseNzLonLat(value) {
  const point = parseLonLat(value);
  return point && validNzCoordinate(point[1], point[0]) ? point : null;
}

export function distanceMeters(a, b) {
  const rad = Math.PI / 180;
  const lat1 = a[1] * rad;
  const lat2 = b[1] * rad;
  const dLat = lat2 - lat1;
  const dLon = (b[0] - a[0]) * rad;
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(Math.max(0, 1 - h)));
}
