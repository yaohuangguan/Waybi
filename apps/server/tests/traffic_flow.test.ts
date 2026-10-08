import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
  fetchNztaTrafficFlow,
  normalizeTrafficFlow,
  normalizeTrafficFlowXml,
} from '../src/traffic_flow.ts';

function samplePayload() {
  return {
    getTrafficConditionsResponse: {
      trafficConditions: {
        lastUpdated: '2026-10-03T09:24:28.587+13:00',
        motorways: [
          {
            name: 'Northern Motorway',
            locations: [
              {
                id: 2,
                name: 'Oteha Valley Rd - Upper Harb Hwy',
                direction: 'Southbound',
                congestion: 'Free Flow',
                startLat: -36.7183,
                startLon: 174.7126,
                endLat: -36.7506,
                endLon: 174.7260,
              },
              {
                id: 4,
                name: 'Upper Harb Hwy - Tristram Ave',
                direction: 'Southbound',
                congestion: 'Heavy',
                startLat: -36.7506,
                startLon: 174.7260,
                endLat: -36.7717,
                endLon: 174.7428,
              },
            ],
          },
        ],
      },
    },
  };
}

test('NZTA traffic conditions normalize to colored motorway segments', () => {
  const state = normalizeTrafficFlow(
    samplePayload(),
    new Date('2026-10-02T20:30:00.000Z'),
  );
  assert.equal(state.segments.length, 2);
  assert.equal(state.segments[0].level, 'free');
  assert.equal(state.segments[1].level, 'heavy');
  assert.equal(state.segments[1].direction, 'Southbound');
  assert.equal(state.sourceUpdatedAt, '2026-10-03T09:24:28.587+13:00');
});

test('namespaced NZTA XML traffic response is normalized', () => {
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
    <ns2:getTrafficConditionsResponse xmlns:ns2="https://infoconnect.highwayinfo.govt.nz/schemas/traffic2">
      <trafficConditions>
        <lastUpdated>2026-10-03T09:24:28.587+13:00</lastUpdated>
        <motorways>
          <name>Northern Motorway</name>
          <locations>
            <id>2</id>
            <name>Oteha Valley Rd - Upper Harb Hwy</name>
            <direction>Southbound</direction>
            <congestion>Heavy</congestion>
            <startLat>-36.7183</startLat>
            <startLon>174.7126</startLon>
            <endLat>-36.7506</endLat>
            <endLon>174.7260</endLon>
          </locations>
        </motorways>
      </trafficConditions>
    </ns2:getTrafficConditionsResponse>`;

  const state = normalizeTrafficFlowXml(
    xml,
    new Date('2026-10-02T20:30:00.000Z'),
  );
  assert.equal(state.segments.length, 1);
  assert.equal(state.segments[0].motorway, 'Northern Motorway');
  assert.equal(state.segments[0].level, 'heavy');
  assert.equal(state.segments[0].start.longitude, 174.7126);
  assert.equal(state.sourceUpdatedAt, '2026-10-03T09:24:28.587+13:00');
});

test('Worker exposes live traffic flow at /api/traffic-flow', async () => {
  const { default: worker } = await import('../src/worker.ts');
  const store = new Map();
  const env = {
    CAMERA_DATA: {
      async get(key) {
        return store.get(key) ?? null;
      },
      async put(key, value) {
        store.set(key, JSON.parse(value));
      },
    },
    ASSETS: { fetch: async () => new Response('asset') },
  };
  const xml = `<getTrafficConditionsResponse>
    <trafficConditions>
      <lastUpdated>${new Date().toISOString()}</lastUpdated>
      <motorways>
        <name>Southern Motorway</name>
        <locations>
          <id>9</id>
          <name>Market Rd - Greenlane</name>
          <direction>Southbound</direction>
          <congestion>Moderate</congestion>
          <startLat>-36.884</startLat><startLon>174.785</startLon>
          <endLat>-36.895</endLat><endLon>174.801</endLon>
        </locations>
      </motorways>
    </trafficConditions>
  </getTrafficConditionsResponse>`;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () =>
    new Response(xml, {
      status: 200,
      headers: { 'content-type': 'application/xml' },
    });
  try {
    const response = await worker.fetch(
      new Request('https://example.test/api/traffic-flow'),
      env,
      { waitUntil() {} },
    );
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.syncStatus, 'live');
    assert.equal(body.segments.length, 1);
    assert.equal(body.segments[0].level, 'moderate');
  } finally {
    globalThis.fetch = originalFetch;
  }
});


test('cached traffic endpoint is read-only even when clients poll repeatedly', async () => {
  const { default: worker } = await import('../src/worker.ts');
  const now = new Date();
  const cached = {
    ...normalizeTrafficFlow(samplePayload(), now),
    checkedAt: new Date(now.getTime() - 30 * 60 * 1000).toISOString(),
  };
  let writes = 0;
  let upstreamCalls = 0;
  const env = {
    CAMERA_DATA: {
      async get() { return cached; },
      async put() { writes++; },
    },
    ASSETS: { fetch: async () => new Response('asset') },
  };
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { upstreamCalls++; throw new Error('should not fetch'); };
  try {
    for (let i = 0; i < 3; i++) {
      const response = await worker.fetch(
        new Request('https://example.test/api/traffic-flow'),
        env,
        { waitUntil() {} },
      );
      assert.equal(response.status, 200);
      assert.equal((await response.json()).segments.length, 2);
    }
    assert.equal(writes, 0);
    assert.equal(upstreamCalls, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('traffic and road-event crons write independently within the daily KV budget', async () => {
  const { default: worker } = await import('../src/worker.ts');
  const snapshots = new Map();
  const pending = [];
  const env = {
    CAMERA_DATA: {
      async get() { return null; },
      async put(key, value) { snapshots.set(key, JSON.parse(value)); },
    },
  };
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url) => new Response(JSON.stringify(
    String(url).includes('livetraffic.com') ? { type: 'FeatureCollection', features: [] } :
      String(url).includes('/events/') ? { response: { roadevent: [] } } : samplePayload()
  ), {
    headers: { 'content-type': 'application/json' },
  });
  try {
    const context = { waitUntil(promise) { pending.push(promise); } };
    await worker.scheduled({ cron: '*/5 * * * *' }, env, context);
    await Promise.all(pending.splice(0));
    assert.deepEqual([...snapshots.keys()], ['waybi:traffic-flow/v2']);
    assert.equal(snapshots.get('waybi:traffic-flow/v2').segments.length, 2);

    await worker.scheduled({ cron: '*/10 * * * *' }, env, context);
    await Promise.all(pending.splice(0));
    assert.deepEqual([...snapshots.keys()].sort(), ['road-events/au-nsw/current', 'road-events/current', 'waybi:traffic-flow/v2']);
    assert.equal(snapshots.get('road-events/current').syncStatus, 'live');
    assert.deepEqual(snapshots.get('road-events/current').events, []);
    assert.equal(snapshots.get('road-events/au-nsw/current').syncStatus, 'live');

    snapshots.clear();
    await worker.scheduled({ cron: '*/15 * * * *' }, env, context);
    await Promise.all(pending.splice(0));
    assert.deepEqual([...snapshots.keys()], []);

    const config = JSON.parse(readFileSync(new URL('../../../wrangler.jsonc', import.meta.url), 'utf8'));
    assert.deepEqual(config.triggers.crons, [
      '*/5 * * * *', '*/10 * * * *', '*/15 * * * *', '0 3 * * *',
    ]);
    // Traffic and road events share snapshots; cameras refresh once per day.
    const daily = 24 * ((60 / 5) + 2 * (60 / 10)) + 1;
    assert.equal(daily, 577);
    assert.ok(daily < 650, 'reserve room for request-driven KV writes');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('traffic flow fetch uses the live no-key NZTA endpoint response', async () => {
  const state = await fetchNztaTrafficFlow(async (url, init) => {
    assert.equal(
      url,
      'https://trafficnz.info/service/traffic-conditions/rest/2',
    );
    assert.match(init.headers['user-agent'], /Waybi/);
    return new Response(JSON.stringify(samplePayload()), {
      headers: { 'content-type': 'application/json' },
    });
  });
  assert.equal(state.syncStatus, 'live');
  assert.equal(state.segments.length, 2);
});
