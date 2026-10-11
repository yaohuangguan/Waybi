import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeOsrmRoutes, maneuverLanes } from '../src/routes.ts';

const lanes = [{ indications: ['left', 'straight'], valid: true }, { indications: ['straight'], valid: false }];
test('a turn uses its own incoming lanes, not every downstream intersection', () => {
  const step = { maneuver: { type: 'turn', modifier: 'left', location: [174.8, -36.9] },
    intersections: [{ location: [174.8, -36.9], lanes },
      { location: [174.81, -36.91], lanes: Array(5).fill({ indications: ['straight'], valid: true }) }] };
  const route = normalizeOsrmRoutes({ routes: [{ legs: [{ steps: [step] }] }] }, 'DRIVE')[0];
  assert.deepEqual(route.steps[0].lanes, lanes);
  assert.equal(route.steps[0].lanes.length, 2);
});
test('missing maneuver lanes never borrow a later junction or motorway lanes', () => {
  assert.deepEqual(maneuverLanes({ intersections: [{}, { lanes }] }), []);
  assert.deepEqual(maneuverLanes({ maneuver: { location: [174.8, -36.9] },
    intersections: [{ location: [174.81, -36.91], lanes }] }), []);
});
test('real wide motorway lane groups remain intact and ordered', () => {
  const motorway = Array.from({ length: 9 }, (_, i) => ({ indications: [i === 8 ? 'right' : 'straight'], valid: i === 8 }));
  assert.deepEqual(maneuverLanes({ intersections: [{ lanes: motorway }] }), motorway);
});
