import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError, apiFetch, describeError, groupFor, parseRetryAfter, rateLimits } from '../src/api';

afterEach(() => rateLimits.clear());

describe('api errors', () => {
  it('parses retry-after seconds and HTTP dates', () => {
    expect(parseRetryAfter('12', 0)).toBe(12000);
    expect(parseRetryAfter('0.5', 0)).toBe(500);
    expect(parseRetryAfter('Wed, 21 Oct 2015 07:28:10 GMT', Date.parse('Wed, 21 Oct 2015 07:28:00 GMT'))).toBe(10000);
    expect(parseRetryAfter('soon', 0)).toBeNull();
    expect(parseRetryAfter(null)).toBeNull();
    expect(parseRetryAfter('999999', 0)).toBe(3_600_000);
  });

  it('groups endpoints so one 429 pauses only its family', () => {
    expect(groupFor('/api/suggest?q=a')).toBe('search');
    expect(groupFor('/api/search?q=a')).toBe('search');
    expect(groupFor('/api/route-options?from=1')).toBe('routing');
    expect(groupFor('/api/cameras')).toBe('other');
  });

  it('turns 429 into a rate-limit error and does not send requests until retry-after passes', async () => {
    vi.useFakeTimers();
    const fetcher = vi.fn().mockResolvedValue(new Response('{"error":"Too many requests"}', { status: 429, headers: { 'retry-after': '20' } }));
    vi.stubGlobal('fetch', fetcher);
    const error = await apiFetch('/api/search?q=sky').catch((e) => e) as ApiError;
    expect(error).toBeInstanceOf(ApiError);
    expect(error.rateLimited).toBe(true);
    expect(error.retryAfterMs).toBe(20000);
    const blocked = await apiFetch('/api/suggest?q=sky').catch((e) => e) as ApiError;
    expect(blocked.rateLimited).toBe(true);
    expect(fetcher).toHaveBeenCalledTimes(1);
    // Other endpoint families keep working.
    fetcher.mockResolvedValueOnce(Response.json({ ok: true }));
    await expect(apiFetch('/api/cameras')).resolves.toEqual({ ok: true });
    vi.advanceTimersByTime(20001);
    fetcher.mockResolvedValueOnce(Response.json([]));
    await expect(apiFetch('/api/search?q=sky')).resolves.toEqual([]);
  });

  it('marks network failures as offline and keeps aborts as aborts', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new TypeError('Failed to fetch')));
    const offline = await apiFetch('/api/search?q=a').catch((e) => e) as ApiError;
    expect(offline.offline).toBe(true);
    expect(describeError(offline).offline).toBe(true);
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new DOMException('Aborted', 'AbortError')));
    await expect(apiFetch('/api/search?q=a')).rejects.toMatchObject({ name: 'AbortError' });
  });

  it('keeps the server message for other HTTP failures', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('{"error":"No open road"}', { status: 503 })));
    const error = await apiFetch('/api/route-options?x=1').catch((e) => e) as ApiError;
    expect(error.message).toBe('No open road');
    expect(error.status).toBe(503);
    expect(error.transient).toBe(true);
  });
});
