import { expect, it, vi } from 'vitest';
vi.mock('maplibre-gl', () => ({ addProtocol: vi.fn(), setWorkerUrl: vi.fn() }));
vi.mock('pmtiles', () => ({ Protocol: class { tile = vi.fn(); } }));
import { inNewZealand, waybiStyle, NZ_TILES, GLOBAL_TILES } from '../src/waybi-map';

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
});
