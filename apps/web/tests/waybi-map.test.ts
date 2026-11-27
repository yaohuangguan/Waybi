import { expect, it, vi } from 'vitest';
vi.mock('maplibre-gl', () => ({ addProtocol: vi.fn(), setWorkerUrl: vi.fn() }));
vi.mock('pmtiles', () => ({ Protocol: class { tile = vi.fn(); } }));
import { inNewZealand, keepOwnLayers, TileFailover, waybiStyle, NZ_TILES, GLOBAL_TILES } from '../src/waybi-map';

it('uses the native NZ archive with legal credits and a global source abroad', () => {
  expect(inNewZealand([174.7633, -36.8485])).toBe(true);
  expect(inNewZealand([151.2, -33.86])).toBe(false);
  const nz = waybiStyle('en', true);
  const world = waybiStyle('en', false);
  expect(nz.sources.openmaptiles).toMatchObject({url:NZ_TILES});
  expect(world.sources.openmaptiles).toMatchObject({url:GLOBAL_TILES});
  expect(nz.sources.openmaptiles).toHaveProperty('attribution', expect.stringContaining('openstreetmap.org/copyright'));
  expect(nz.sources.openmaptiles).toHaveProperty('attribution', expect.stringContaining('/map-licenses.txt'));
});

it('adds Chinese fallback labels without changing the shared base style', () => {
  const zh = waybiStyle('zh', true);
  const en = waybiStyle('en', true);
  expect(JSON.stringify(zh)).toContain('name:zh');
  expect(JSON.stringify(en)).not.toContain('name:zh');
  expect(zh.sources.openmaptiles).toHaveProperty('attribution', expect.stringContaining('地图版权'));
  expect(en.sources.openmaptiles).toHaveProperty('attribution', expect.stringContaining('Map credits'));
});

it('falls back at once when the hosted archive never worked, but tolerates isolated errors once it has', () => {
  const unreachable = new TileFailover(4, 30_000, 300_000);
  expect(unreachable.recordError(0)).toBe(true);
  expect(unreachable.blocked(1000)).toBe(true);

  const failover = new TileFailover(4, 30_000, 300_000);
  failover.recordSuccess();
  expect(failover.recordError(0)).toBe(false);
  expect(failover.recordError(1000)).toBe(false);
  expect(failover.recordError(2000)).toBe(false);
  // Old errors fall out of the window.
  expect(failover.recordError(40_000)).toBe(false);
  expect(failover.recordError(41_000)).toBe(false);
  expect(failover.recordError(42_000)).toBe(false);
  expect(failover.recordError(43_000)).toBe(true);
  expect(failover.blocked(100_000)).toBe(true);
  expect(failover.recordError(100_000)).toBe(false);
  // After the cool-down the hosted archive is tried again.
  expect(failover.blocked(343_001)).toBe(false);
});

it('keeps Waybi route layers when the label language or tile source changes', () => {
  const previous = waybiStyle('en', true);
  previous.sources['waybi-route'] = { type: 'geojson', data: { type: 'FeatureCollection', features: [] } };
  previous.layers.push({ id: 'waybi-route-line', type: 'line', source: 'waybi-route' });
  const next = keepOwnLayers(previous, waybiStyle('zh', false));
  expect(next.sources).toHaveProperty('waybi-route');
  expect(next.layers.at(-1)?.id).toBe('waybi-route-line');
  expect(next.sources.openmaptiles).toMatchObject({ url: GLOBAL_TILES });
  expect(JSON.stringify(next.layers)).toContain('name:zh');
  expect(keepOwnLayers(undefined, waybiStyle('en', true)).layers.some(layer => layer.id.startsWith('waybi-'))).toBe(false);
});
