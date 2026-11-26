import test from 'node:test';
import assert from 'node:assert/strict';
import { conciseExitInstructions } from '../src/route_instructions.ts';
import { normalizeOsrmRoutes } from '../src/routes.ts';

// Steps as the NZ Valhalla graph returned them for SH 1 northbound exit 414,
// whose OSM ramp lists every town on the sign but not Constellation Drive.
const motorway = { name: 'Auckland Northern Motorway', ref: 'SH 1', distance: 6009,
  maneuver: { type: 'fork', modifier: 'slight right',
    instruction: 'Keep right to stay on SH 1/Auckland Northern Motorway towards Whangarei.' } };
const exit414 = { name: '', exits: '414', distance: 872,
  destinations: 'SH 18: Upper Harbour Highway, Greenhithe, Waitakere, Mairangi Bay, AUT Millennium',
  maneuver: { type: 'off ramp', modifier: 'slight left',
    instruction: 'Take exit 414 onto SH 18/Upper Harbour Highway towards Greenhithe/Waitakere/Mairangi Bay/AUT Millennium.' } };
const constellation = { name: 'Constellation Drive', distance: 1166, destinations: 'Mairangi Bay, AUT Millenium',
  maneuver: { type: 'turn', modifier: 'right', instruction: 'Turn right towards Mairangi Bay/AUT Millenium.' } };
const arrive = { name: 'Constellation Drive', distance: 0,
  maneuver: { type: 'arrive', modifier: 'right', instruction: 'Your destination is on the right.' } };

test('a motorway exit names the road it leads to, not every town on the ramp', () => {
  assert.deepEqual(conciseExitInstructions([motorway, exit414, constellation, arrive], 'en'), [
    'Keep right to stay on SH 1/Auckland Northern Motorway towards Whangarei.',
    'Take exit 414 towards Constellation Drive.',
    'Turn right onto Constellation Drive.',
    'Your destination is on the right.',
  ]);
});

test('Chinese guidance gets the same short exit and street', () => {
  const zh = conciseExitInstructions([exit414, constellation], 'zh');
  assert.deepEqual(zh, ['走414号出口，前往Constellation Drive。', '右转进入Constellation Drive。']);
});

test('the other branch of the same exit names the state highway it joins', () => {
  const upperHarbour = { name: 'Upper Harbour Highway', ref: 'SH 18', distance: 350,
    maneuver: { type: 'turn', modifier: 'left', instruction: 'Turn left towards SH 18/Waitakere.' } };
  assert.deepEqual(conciseExitInstructions([exit414, upperHarbour], 'en'), [
    'Take exit 414 towards SH 18/Upper Harbour Highway.',
    'Turn left onto SH 18/Upper Harbour Highway.',
  ]);
});

test('an unnamed fork partway along the ramp is skipped to find the street', () => {
  const rampFork = { name: '', distance: 200,
    maneuver: { type: 'fork', modifier: 'slight left', instruction: 'Keep left towards Mairangi Bay.' } };
  const fork = { name: 'Constellation Drive', distance: 1127,
    maneuver: { type: 'fork', modifier: 'slight left', instruction: 'Keep left to take Constellation Drive towards Mairangi Bay.' } };
  assert.deepEqual(conciseExitInstructions([{ ...exit414, exits: undefined }, rampFork, fork], 'en'), [
    'Take the exit towards Constellation Drive.',
    'Keep left towards Mairangi Bay.',
    // Already names the street, so the engine's sentence stays.
    'Keep left to take Constellation Drive towards Mairangi Bay.',
  ]);
});

test('an exit with no named road nearby keeps the engine sentence', () => {
  const longRamp = { name: '', distance: 3500, maneuver: { type: 'fork', modifier: 'slight left', instruction: 'Keep left.' } };
  const original = conciseExitInstructions([exit414, longRamp, constellation], 'en');
  assert.equal(original[0], exit414.maneuver.instruction);
  assert.equal(original[2], constellation.maneuver.instruction);
  assert.deepEqual(conciseExitInstructions([exit414, arrive], 'en'),
    [exit414.maneuver.instruction, arrive.maneuver.instruction]);
});

test('route options carry the concise exit wording to the app', () => {
  const payload = { routes: [{ distance: 8047, duration: 400, legs: [{ steps: [motorway, exit414, constellation, arrive] }] }] };
  const steps = normalizeOsrmRoutes(payload, 'DRIVE', 'en')[0].steps;
  assert.equal(steps[1].instruction, 'Take exit 414 towards Constellation Drive.');
  assert.equal(steps[2].instruction, 'Turn right onto Constellation Drive.');
});
