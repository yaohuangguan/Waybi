import test from 'node:test';
import assert from 'node:assert/strict';
import {
  fetchNztaCameras,
  parseNztaPage,
  parseNztaReaderText,
} from '../src/sync.ts';

test('rejects a challenge page instead of deleting known cameras', () => {
  assert.throws(() => parseNztaPage('<html><body>challenge</body></html>'), /update date not found/);
});

test('rejects a partial table instead of replacing all cameras', () => {
  const html = '<main><p>Last update: 26 August 2026</p><h3>Auckland</h3><table><tr><td>CBD</td><td>Queen Street</td><td>Spot speed</td><td>-36.850</td><td>174.764</td></tr></table></main>';
  assert.throws(() => parseNztaPage(html), /refusing untrusted update/);
});


function readerText(date, count = 60) {
  const rows = Array.from({ length: count }, (_, index) => {
    const latitude = (-36 - index * 0.01).toFixed(6);
    const longitude = (174 + index * 0.01).toFixed(6);
    return `Test Suburb ${index}\tTest Road ${index}\tSpot speed\t${latitude}\t${longitude}`;
  });
  return [
    `Last update: ${date}`,
    'Auckland',
    'Suburb\tLocation\tCamera type\tGPS coordinates',
    'Latitude\tLongitude',
    ...rows,
  ].join('\n');
}

test('parses tab-preserving reader fallback without losing published fields', () => {
  const parsed = parseNztaReaderText(readerText('1 October 2026'));
  assert.equal(parsed.sourceUpdatedAt, '2026-10-01');
  assert.equal(parsed.cameras.length, 60);
  assert.deepEqual(
    {
      region: parsed.cameras[0].region,
      suburb: parsed.cameras[0].suburb,
      location: parsed.cameras[0].location,
      type: parsed.cameras[0].type,
    },
    {
      region: 'Auckland',
      suburb: 'Test Suburb 0',
      location: 'Test Road 0',
      type: 'Spot speed',
    },
  );
});

test('falls back to the validated reader when NZTA direct fetch is challenged', async () => {
  const calls = [];
  const data = await fetchNztaCameras(async (url) => {
    calls.push(String(url));
    if (calls.length === 1) {
      return new Response('<html><body>challenge</body></html>');
    }
    return new Response(readerText('1 October 2026'));
  });
  assert.equal(data.fetchMode, 'reader-fallback');
  assert.equal(data.sourceUpdatedAt, '2026-10-01');
  assert.equal(data.cameras.length, 60);
  assert.equal(calls.length, 2);
});
