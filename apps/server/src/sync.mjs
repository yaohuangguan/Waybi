import { load } from 'cheerio';
import { createHash } from 'node:crypto';

export const SOURCE_URL = 'https://www.nzta.govt.nz/travelling-on-our-roads/safety-cameras/about-safety-cameras/fixed-safety-camera-locations';
export const READER_URL = 'https://r.jina.ai/http://nzta.govt.nz/travelling-on-our-roads/safety-cameras/about-safety-cameras/fixed-safety-camera-locations';

const REGIONS = new Set([
  'Northland',
  'Auckland',
  'Waikato',
  'Bay of Plenty',
  'Taranaki',
  'Manawatū-Whanganui',
  'Wellington',
  'Canterbury',
  'Otago',
  'Southland'
]);

export function cameraId(location, latitude, longitude) {
  return createHash('sha256')
    .update(`${location.toLowerCase()}|${latitude.toFixed(6)}|${longitude.toFixed(6)}`)
    .digest('hex')
    .slice(0, 16);
}

function sourceUpdatedAtFrom(text) {
  const dateMatch = text.match(
    /Last\s+update\s*:\s*(\d{1,2})\s+([A-Za-z]+)\s+(20\d{2})/i
  );
  if (!dateMatch) {
    throw new Error('NZTA update date not found; page may be blocked or its layout changed');
  }
  const parsedDate = new Date(
    `${dateMatch[1]} ${dateMatch[2]} ${dateMatch[3]} 12:00:00 GMT`
  );
  if (Number.isNaN(parsedDate.getTime())) {
    throw new Error('NZTA update date invalid');
  }
  return parsedDate.toISOString().slice(0, 10);
}

function numberFromCell(value) {
  return Number(String(value ?? '').replace(/[^\d.-]/g, ''));
}

function cameraRecord(region, suburb, location, type, latitude, longitude, updatedAt) {
  return {
    id: cameraId(location, latitude, longitude),
    name: `${location} — ${suburb}`,
    region,
    suburb,
    location,
    type,
    latitude,
    longitude,
    source: SOURCE_URL,
    updatedAt
  };
}

function validateSnapshot(cameras, sourceUpdatedAt) {
  const distinct = [...new Map(cameras.map((camera) => [camera.id, camera])).values()];
  if (distinct.length < 50 || distinct.length > 1000) {
    throw new Error(
      `NZTA page parsed ${distinct.length} cameras; refusing untrusted update`
    );
  }
  if (!sourceUpdatedAt) throw new Error('NZTA snapshot has no source update date');

  for (const camera of distinct) {
    if (
      !camera.region ||
      !camera.suburb ||
      !camera.location ||
      !camera.type ||
      !(camera.latitude > -48 && camera.latitude < -34) ||
      !(camera.longitude > 166 && camera.longitude < 179)
    ) {
      throw new Error('NZTA snapshot contains an incomplete or invalid camera row');
    }
  }
  return { cameras: distinct, sourceUpdatedAt };
}

export function parseNztaPage(html) {
  const $ = load(html);
  const body = $('main').length ? $('main') : $('body');
  const updatedAt = sourceUpdatedAtFrom(body.text());
  let region = '';
  const cameras = [];

  body.find('h2, h3, h4, table').each((_, element) => {
    if (element.tagName !== 'table') {
      const heading = $(element).text().replace(/\s+/g, ' ').trim();
      if (REGIONS.has(heading)) region = heading;
      return;
    }

    $(element)
      .find('tr')
      .each((__, row) => {
        const cells = $(row)
          .find('td')
          .map((___, cell) => $(cell).text().replace(/\s+/g, ' ').trim())
          .get();
        if (cells.length < 5) return;
        const [suburb, location, type, latText, lonText] = cells;
        const latitude = numberFromCell(latText);
        const longitude = numberFromCell(lonText);
        if (!location || !type) return;
        if (!(latitude > -48 && latitude < -34 && longitude > 166 && longitude < 179)) {
          return;
        }
        cameras.push(
          cameraRecord(region, suburb, location, type, latitude, longitude, updatedAt)
        );
      });
  });

  return validateSnapshot(cameras, updatedAt);
}

export function parseNztaReaderText(text) {
  const updatedAt = sourceUpdatedAtFrom(text);
  let region = '';
  const cameras = [];

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;
    if (REGIONS.has(line)) {
      region = line;
      continue;
    }

    const cells = rawLine
      .split('\t')
      .map((value) => value.replace(/\u00a0/g, ' ').trim());
    if (cells.length < 5) continue;
    const [suburb, location, type, latText, lonText] = cells;
    if (suburb === 'Suburb' || suburb === 'Latitude') continue;
    const latitude = numberFromCell(latText);
    const longitude = numberFromCell(lonText);
    if (!location || !type) continue;
    if (!(latitude > -48 && latitude < -34 && longitude > 166 && longitude < 179)) {
      continue;
    }
    cameras.push(
      cameraRecord(region, suburb, location, type, latitude, longitude, updatedAt)
    );
  }

  return validateSnapshot(cameras, updatedAt);
}

export async function fetchNztaCameras(fetcher = fetch) {
  let directError = null;
  try {
    const response = await fetcher(SOURCE_URL, {
      headers: {
        'user-agent': 'Waybi/1.0 (+https://github.com/yaohuangguan/Waybi)',
        accept: 'text/html'
      },
      signal: AbortSignal.timeout(15000)
    });
    if (!response.ok) throw new Error(`NZTA returned HTTP ${response.status}`);
    return {
      ...parseNztaPage(await response.text()),
      fetchMode: 'direct'
    };
  } catch (error) {
    directError = String(error?.message || error);
  }

  const reader = await fetcher(READER_URL, {
    headers: {
      accept: 'text/plain',
      'X-Return-Format': 'text'
    },
    signal: AbortSignal.timeout(20000)
  });
  if (!reader.ok) {
    throw new Error(
      `NZTA direct fetch failed (${directError}); reader fallback returned HTTP ${reader.status}`
    );
  }
  try {
    return {
      ...parseNztaReaderText(await reader.text()),
      fetchMode: 'reader-fallback'
    };
  } catch (error) {
    throw new Error(
      `NZTA direct fetch failed (${directError}); reader fallback invalid: ${error?.message || error}`
    );
  }
}
