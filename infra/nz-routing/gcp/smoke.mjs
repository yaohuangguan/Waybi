import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { fetchNzRouting } from '../../../apps/server/src/nz_routing.ts';
import { normalizeOsrmRoutes, routeOptions } from '../../../apps/server/src/routes.ts';
import { cloudRunIdentityToken } from '../../../apps/server/src/cloud_run_auth.ts';

// Pipe gcloud auth print-identity-token on stdin. Never put a token in argv,
// a report, or a URL. Node 24 runs the existing TypeScript provider directly.
const [endpoint, output] = process.argv.slice(2);
const origin = new URL(endpoint).origin;
assert.equal(origin, endpoint, 'Use the canonical service URL');
assert.ok(origin.endsWith('.run.app'));
const credential = readFileSync(0, 'utf8').trim();
assert.ok(credential.length > 100, 'Pipe an identity token or service account JSON on stdin');
const serviceAccount = credential.startsWith('{');
const token = serviceAccount
  ? await cloudRunIdentityToken(credential, origin, AbortSignal.timeout(15000)) : credential;
const env = { WAYBI_NZ_ROUTING_URL: endpoint, ...(serviceAccount
  ? { WAYBI_NZ_ROUTING_GCP_SERVICE_ACCOUNT: credential } : { WAYBI_NZ_ROUTING_TOKEN: credential }) };
const nativeFetch = globalThis.fetch;
let wireJsonBytes = 0;
// Any failure of the owned engine must fail this probe, not accidentally test
// the public fallback while reporting that Cloud Run succeeded.
globalThis.fetch = async (url, init) => {
  assert.ok([origin, 'https://oauth2.googleapis.com'].includes(new URL(String(url)).origin),
    'Unexpected fallback in owned-engine probe');
  const response = await nativeFetch(url, init);
  if (new URL(String(url)).pathname === '/route' && response.ok) {
    wireJsonBytes = Buffer.byteLength(await response.clone().text());
  }
  return response;
};
const measurements = [];
const report = { measuredAt: new Date().toISOString(), endpoint, measurements };
function save() { if (output) writeFileSync(output, JSON.stringify(report, null, 2) + '\n'); }
try {
  const unauthorized = await nativeFetch(`${endpoint}/status`, { signal: AbortSignal.timeout(15000) });
  assert.ok([401, 403].includes(unauthorized.status), 'IAM must reject anonymous requests');
  report.anonymousStatus = unauthorized.status;
  // With --no-deploy-health-check this is the first authorized request. The
  // first sample includes scale-from-zero; warm requests are measured apart.
  const first = performance.now();
  const response = await nativeFetch(`${endpoint}/status`, { headers: { authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(60000) });
  assert.equal(response.status, 200);
  report.firstAuthorizedStatusMs = Math.round(performance.now() - first);
  report.engine = await response.json();
  const pairs = [
    ['Auckland-airport', [[174.7633, -36.8485], [174.785, -37.0067]]],
    ['Auckland-Hamilton', [[174.7633, -36.8485], [175.2793, -37.787]]],
    ['Christchurch-Queenstown', [[172.6362, -43.5321], [168.6626, -45.0312]]],
    ['Hamilton-Wellington', [[175.2793, -37.787], [174.7762, -41.2866]]],
  ];
  let baseRoutes;
  for (let repeat = 0; repeat < 3; repeat++) {
    for (const [name, points] of pairs) {
      const started = performance.now();
      const raw = await fetchNzRouting(env, points, 'DRIVE', { alternatives: true });
      const routes = normalizeOsrmRoutes(raw, 'DRIVE');
      assert.ok(routes[0]?.coordinates.length > 1 && routes[0]?.steps.length > 1);
      measurements.push({ name, repeat, ms: Math.round(performance.now() - started), routes: routes.length,
        wireJsonBytes, metres: routes[0].distanceMeters,
        steps: routes[0].steps.length, laneSteps: routes[0].steps.filter(s => s.lanes.length).length });
      if (name === 'Auckland-Hamilton') baseRoutes = routes;
    }
  }
  for (const mode of ['WALK', 'BICYCLE']) {
    const started = performance.now();
    const raw = await fetchNzRouting(env, [[174.7633, -36.8485], [174.774, -36.852]], mode, { language: 'zh' });
    const routes = normalizeOsrmRoutes(raw, mode);
    assert.ok(routes[0]?.steps.length > 1);
    measurements.push({ name: mode, ms: Math.round(performance.now() - started), routes: routes.length,
      wireJsonBytes, metres: routes[0].distanceMeters });
  }
  const step = baseRoutes[0].steps.find(s => s.maneuver === 'on ramp') || baseRoutes[0].steps[2];
  assert.ok(step?.location);
  const now = new Date();
  const closure = { id: 'staging-synthetic-closure', type: 'roadClosure',
    location: { longitude: step.location[0], latitude: step.location[1] }, geometry: [], headingDegrees: null,
    roadName: step.name, severity: 'critical', observation: 'official', confidence: 1,
    validFrom: new Date(now.getTime() - 60000).toISOString(), validUntil: new Date(now.getTime() + 3600000).toISOString(),
    source: { provider: 'Synthetic staging validation (not an actual NZTA closure)', country: 'NZ',
      region: null, sourceId: 'probe', updatedAt: now.toISOString() }, metadata: {} };
  const state = { events: [closure], syncStatus: 'live', retrievedAt: now.toISOString() };
  const started = performance.now();
  const plan = await routeOptions(pairs[1][1][0], pairs[1][1][1], { ...env,
    CAMERA_DATA: { async get() { return state; } } }, [], ['DRIVE'], () => {},
    { forceIndependent: true, alternatives: false });
  assert.equal(plan.roadAwareness.avoidance, 'detour');
  assert.ok(!plan.options[0].closureIds?.length);
  assert.notDeepEqual(plan.options[0].coordinates, baseRoutes[0].coordinates);
  measurements.push({ name: 'synthetic-closure-detour', ms: Math.round(performance.now() - started),
    avoidance: plan.roadAwareness.avoidance, road: step.name, metres: plan.options[0].distanceMeters,
    changed: true });
  const warm = measurements.filter(m => m.repeat !== undefined).map(m => m.ms).sort((a, b) => a - b);
  report.warmRoutingP50Ms = warm[Math.ceil(warm.length * .5) - 1];
  report.warmRoutingP95Ms = warm[Math.ceil(warm.length * .95) - 1];
  report.note = 'Small sample; wall time includes test-client network latency. Not a concurrency or DAU capacity guarantee.';
  report.passed = true;
} catch (error) {
  report.passed = false;
  report.error = error.message;
  process.exitCode = 1;
} finally {
  globalThis.fetch = nativeFetch;
  save();
  console.log(JSON.stringify(report, null, 2));
}
