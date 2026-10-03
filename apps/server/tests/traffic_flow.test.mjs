import test from 'node:test';
import assert from 'node:assert/strict';

import {
  fetchNztaTrafficFlow,
  normalizeTrafficFlow,
  normalizeTrafficFlowXml,
} from '../src/traffic_flow.mjs';

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
  const { default: worker } = await import('../src/worker.mjs');
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
