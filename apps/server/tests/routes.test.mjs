import test from 'node:test';
import assert from 'node:assert/strict';
import { routeOptions } from '../src/routes.mjs';

test('Google driving alternatives request traffic on the polyline', async () => {
  const originalFetch = globalThis.fetch;
  const requests = [];
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(init.body);
    requests.push(body);
    return new Response(JSON.stringify({ routes: body.travelMode === 'DRIVE' ? [{
      duration: '100s',
      staticDuration: '90s',
      distanceMeters: 1000,
      polyline: { encodedPolyline: 'abc' },
      travelAdvisory: { speedReadingIntervals: [
        { endPolylinePointIndex: 3, speed: 'NORMAL' },
        { startPolylinePointIndex: 3, endPolylinePointIndex: 5, speed: 'SLOW' }
      ] },
      legs: []
    }] : [] }), { headers: { 'content-type': 'application/json' } });
  };
  try {
    const plan = await routeOptions([174.76, -36.85], [174.77, -36.86], { GOOGLE_ROUTES_API_KEY: 'test' });
    const drive = requests.find((request) => request.travelMode === 'DRIVE');
    assert.deepEqual(drive.extraComputations, ['TRAFFIC_ON_POLYLINE']);
    assert.equal(drive.routingPreference, 'TRAFFIC_AWARE_OPTIMAL');
    assert.equal(plan.trafficAvailable, true);
    assert.deepEqual(plan.options[0].trafficIntervals.map((interval) => interval.speed), ['normal', 'slow']);
  } finally {
    globalThis.fetch = originalFetch;
  }
});


test('commute ETA can request only the driving route mode', async () => {
  const originalFetch = globalThis.fetch;
  const requests = [];
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(init.body);
    requests.push(body);
    return new Response(JSON.stringify({
      routes: [{
        duration: '600s',
        staticDuration: '540s',
        distanceMeters: 8000,
        polyline: { encodedPolyline: 'abc' },
        travelAdvisory: { speedReadingIntervals: [] },
        legs: []
      }]
    }), { headers: { 'content-type': 'application/json' } });
  };
  try {
    const plan = await routeOptions(
      [174.76, -36.85],
      [174.77, -36.86],
      { GOOGLE_ROUTES_API_KEY: 'test' },
      [],
      ['DRIVE']
    );
    assert.deepEqual(requests.map((request) => request.travelMode), ['DRIVE']);
    assert.equal(plan.options.length, 1);
    assert.equal(plan.options[0].mode, 'drive');
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("transit-only requests return the transit route instead of falling back to driving", async () => {
  const originalFetch = globalThis.fetch;
  const requests = [];
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(init.body);
    requests.push(body);
    return new Response(JSON.stringify({
      routes: [{
        duration: "900s",
        staticDuration: "900s",
        distanceMeters: 6500,
        polyline: { encodedPolyline: "abc" },
        legs: [{
          steps: [{
            distanceMeters: 1200,
            staticDuration: "300s",
            startLocation: { latLng: { latitude: -36.85, longitude: 174.76 } },
            transitDetails: {
              headsign: "Britomart",
              stopCount: 4,
              stopDetails: {
                departureStop: { name: "Start" },
                arrivalStop: { name: "Britomart" }
              },
              transitLine: {
                nameShort: "70",
                vehicle: { type: "BUS" },
                agencies: [{ name: "Auckland Transport" }]
              }
            }
          }]
        }]
      }]
    }), { headers: { "content-type": "application/json" } });
  };
  try {
    const plan = await routeOptions(
      [174.76, -36.85],
      [174.77, -36.86],
      { GOOGLE_ROUTES_API_KEY: "test" },
      [],
      ["TRANSIT"]
    );
    assert.deepEqual(requests.map((request) => request.travelMode), ["TRANSIT"]);
    assert.equal(plan.provider, "google");
    assert.equal(plan.options.length, 1);
    assert.equal(plan.options[0].mode, "transit");
    assert.equal(plan.options[0].transit[0].lineName, "70");
  } finally {
    globalThis.fetch = originalFetch;
  }
});
