import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { matchRouteClosures, crossesExcludedRoads } from '../../../apps/server/src/routing_closures.ts';

const [origin, output, version] = process.argv.slice(2);
const fetchWorker = (url, init = {}) => fetch(url, { ...init,
  ...(version ? { headers: { 'Cloudflare-Workers-Version-Overrides': `waybi="${version}"` } } : {}) });
const report = { origin, startedAt: new Date().toISOString(), probes: [] };
try {
  let driving;
  for (const mode of ['drive', 'walk', 'bicycle']) {
    const query = new URLSearchParams({ from: '174.7633,-36.8485',
      to: mode === 'drive' ? '175.2793,-37.787' : '174.774,-36.852',
      mode, provider: 'independent', alternatives: 'false', lang: 'zh' });
    const started = performance.now();
    const response = await fetchWorker(`${origin}/api/route-options?${query}`, { signal: AbortSignal.timeout(45000) });
    assert.equal(response.status, 200, `${mode}: HTTP ${response.status}`);
    const body = await response.json();
    assert.equal(body.provider, 'independent');
    const route = body.options.find(route => route.mode === mode);
    assert.ok(route?.coordinates.length > 1 && route.steps.length > 1, `${mode}: route missing`);
    assert.ok(!route.closureIds?.length && !route.restrictedRoadIds?.length, `${mode}: route is blocked`);
    if (mode === 'drive') driving = route;
    report.probes.push({ mode, ms: Math.round(performance.now() - started),
      metres: route.distanceMeters, steps: route.steps.length,
      laneSteps: route.steps.filter(step => step.lanes?.length).length,
      avoidance: body.roadAwareness?.avoidance ?? null });
  }
  // Exercise a deliberately excluded directed road through the public API.
  // This is a synthetic test, not a claim that this road is actually closed.
  const step = driving.steps.find(step => step.maneuver === 'on ramp') || driving.steps[2];
  const now = new Date();
  const closure = { id: 'production-smoke-synthetic', type: 'roadClosure',
    location: { longitude: step.location[0], latitude: step.location[1] },
    geometry: [], headingDegrees: null, roadName: step.name, severity: 'critical',
    observation: 'official', confidence: 1, validFrom: null, validUntil: null,
    source: { provider: 'Synthetic validation only', country: 'NZ', region: null,
      sourceId: 'synthetic-probe', updatedAt: now.toISOString() }, metadata: {} };
  const exclusions = matchRouteClosures(driving, [closure], now).flatMap(match => match.locations);
  assert.ok(exclusions.length && exclusions.length <= 32, 'No usable test exclusion');
  const query = new URLSearchParams({ from: '174.7633,-36.8485', to: '175.2793,-37.787',
    mode: 'drive', provider: 'independent', alternatives: 'false',
    avoid: exclusions.map(point => `${point.lon},${point.lat},${point.heading}`).join(';') });
  const started = performance.now();
  const response = await fetchWorker(`${origin}/api/route-options?${query}`, { signal: AbortSignal.timeout(45000) });
  assert.equal(response.status, 200);
  const detour = (await response.json()).options.find(route => route.mode === 'drive');
  assert.ok(detour?.coordinates.length > 1 && !detour.closureIds?.length);
  assert.equal(crossesExcludedRoads(detour, exclusions), false);
  assert.notDeepEqual(detour.coordinates, driving.coordinates);
  report.probes.push({ mode: 'synthetic-directed-road-exclusion',
    ms: Math.round(performance.now() - started), changed: true, metres: detour.distanceMeters });
  const crossSea = await fetchWorker(`${origin}/api/route-options?from=174.76,-36.85&to=151.21,-33.86&provider=independent&mode=drive`);
  assert.equal(crossSea.status, 422);
  report.crossTasmanStatus = crossSea.status;
  const homepage = await fetchWorker(origin, { signal: AbortSignal.timeout(15000) });
  assert.equal(homepage.status, 200);
  report.homeStatus = homepage.status;
  report.passed = true;
} catch (error) {
  report.passed = false;
  report.error = error.message;
  process.exitCode = 1;
} finally {
  report.completedAt = new Date().toISOString();
  if (output) writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report, null, 2));
}
