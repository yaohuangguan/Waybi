import { describe, expect, it, vi } from 'vitest';
import { fetchRoutePlan, decodePolyline, formatModeDuration, routeFromOption, type RouteOption } from '../src/route-planner';
import { lookAheadCenter } from '../src/navigation-view';

describe('route planning and navigation geometry', () => {
  it('sends coordinates in longitude/latitude order, preserves stops and abort signal', async () => {
    const plan = { provider: 'waybi', options: [], stopsApplied: 1, trafficAvailable: false };
    const fetcher = vi.fn().mockResolvedValue(Response.json(plan));
    vi.stubGlobal('fetch', fetcher);
    const signal = new AbortController().signal;
    expect(await fetchRoutePlan('', [174.7,-36.8], [174.8,-36.9], [[174.75,-36.85]], signal)).toEqual(plan);
    const url = new URL(fetcher.mock.calls[0][0], 'https://waybi.co');
    expect(url.searchParams.get('from')).toBe('174.7,-36.8');
    expect(url.searchParams.get('stops')).toBe('174.75,-36.85');
    expect(url.searchParams.get('provider')).toBe('independent');
    expect(url.searchParams.get('mode')).toBe('drive');
    expect(fetcher.mock.calls[0][1].signal).toBe(signal);
  });
  it.each([true, false])('surfaces route failures with or without a JSON message (%s)', async (json) => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(json ? '{"error":"No open road"}' : 'offline', {status:503})));
    await expect(fetchRoutePlan('', [0,0], [1,1], [])).rejects.toThrow(json ? 'No open road' : 'HTTP 503');
  });
  it('decodes positive and negative polyline deltas and prefers explicit geometry', () => {
    const coordinates = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(coordinates).toEqual([[-120.2,38.5],[-120.95,40.7],[-126.453,43.252]]);
    expect(decodePolyline('')).toEqual([]);
    const option = {encodedPolyline:'_p~iF~ps|U', coordinates:[[174.7,-36.8],[174.8,-36.9]], distanceMeters:200, durationSeconds:60} as RouteOption;
    expect(routeFromOption(option)).toMatchObject({coordinates:option.coordinates,distance:200,duration:60,steps:[]});
    expect(routeFromOption({...option, coordinates:undefined}).coordinates).toEqual([[-120.2,38.5]]);
  });
  it.each([[null,'—'],[NaN,'—'],[0,'—'],[1,'1 min'],[3540,'59 min'],[3600,'1 h'],[3660,'1 h 1 min']])('formats duration %s', (seconds, expected) => {
    expect(formatModeDuration(seconds)).toBe(expected);
  });
  it('follows route bearing without a compass and honors a valid GPS heading', () => {
    const route = {coordinates:[[174,-37],[174.01,-37]],distance:1000,duration:60,steps:[]} as any;
    expect(lookAheadCenter([174,-37], null, route)[0]).toBeGreaterThan(174);
    expect(lookAheadCenter([174,-37], 0, route)[1]).toBeGreaterThan(-37);
    expect(lookAheadCenter([174,-37], NaN, route, 0)).toEqual([174,-37]);
  });
  it('keeps walking requests and language inside independent routing', async () => {
    const fetcher = vi.fn().mockResolvedValue(Response.json({provider:'independent', options:[]}));
    vi.stubGlobal('fetch', fetcher);
    await fetchRoutePlan('', [174,-37], [175,-37], [], undefined, 'walk', 'zh');
    const url = new URL(fetcher.mock.calls[0][0], 'https://waybi.co');
    expect(url.searchParams.get('provider')).toBe('independent');
    expect(url.searchParams.get('mode')).toBe('walk');
    expect(url.searchParams.get('lang')).toBe('zh');
  });
  it('refuses a legacy provider response instead of drawing it on the independent map', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(Response.json({provider:'google',options:[]})));
    await expect(fetchRoutePlan('', [174,-37], [175,-37], [])).rejects.toThrow('Independent routing');
  });
  it('excludes closed roads and bus-only routes while preserving a legal alternative', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(Response.json({provider:'independent',options:[
      {id:'closed',closureIds:['closure-1']}, {id:'bus-only',restrictedRoadIds:['lane-1']}, {id:'clear'}
    ]})));
    expect((await fetchRoutePlan('', [174,-37], [175,-37], [])).options.map(option => option.id)).toEqual(['clear']);
  });
});
