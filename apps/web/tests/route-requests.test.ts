import { describe, expect, it } from 'vitest';
import { Backoff, RouteRequestCoordinator, journeySummaryKind, layoutSignature } from '../src/route-requests';

describe('route request coordination', () => {
  it('backs off exponentially, honours retry-after and resets on success', () => {
    const backoff = new Backoff(2000, 16000);
    expect(backoff.fail(0)).toBe(2000);
    expect(backoff.ready(1999)).toBe(false);
    expect(backoff.ready(2000)).toBe(true);
    expect(backoff.fail(2000)).toBe(4000);
    expect(backoff.fail(6000)).toBe(8000);
    expect(backoff.fail(14000)).toBe(16000);
    expect(backoff.fail(30000)).toBe(16000);
    expect(backoff.fail(50000, 45000)).toBe(45000);
    backoff.succeed();
    expect(backoff.ready(50001)).toBe(true);
    expect(backoff.fail(60000)).toBe(2000);
  });

  it('does not let GPS fixes abort a plan that is already in flight', () => {
    const requests = new RouteRequestCoordinator();
    const first = requests.begin('auto');
    expect(requests.canStart('auto')).toBe(false);
    expect(requests.canStart('reroute')).toBe(false);
    expect(first.signal.aborted).toBe(false);
    // A user action still replaces the pending request.
    expect(requests.canStart('user')).toBe(true);
    const second = requests.begin('user');
    expect(first.signal.aborted).toBe(true);
    expect(requests.isCurrent(second)).toBe(true);
    requests.succeed(second);
    expect(requests.pending).toBe(false);
  });

  it('waits for the backoff after a failure and only notifies once per streak', () => {
    const requests = new RouteRequestCoordinator(new Backoff(1000, 8000));
    const a = requests.begin('auto');
    expect(requests.fail(a, null, 0)).toEqual({ delay: 1000, notify: true });
    expect(requests.canStart('auto', 500)).toBe(false);
    expect(requests.canStart('auto', 1000)).toBe(true);
    const b = requests.begin('auto');
    expect(requests.fail(b, null, 1000)).toEqual({ delay: 2000, notify: false });
    const c = requests.begin('user');
    expect(requests.fail(c, 30000, 3000)).toEqual({ delay: 30000, notify: true });
    requests.reset();
    expect(requests.canStart('auto', 3001)).toBe(true);
  });

  it('ignores the result of a request that was superseded', () => {
    const requests = new RouteRequestCoordinator();
    const old = requests.begin('auto');
    const current = requests.begin('user');
    requests.succeed(old);
    expect(requests.isCurrent(current)).toBe(true);
    expect(requests.pending).toBe(true);
    requests.cancel();
    expect(current.signal.aborted).toBe(true);
    expect(requests.pending).toBe(false);
  });
});

describe('journey summary and layout helpers', () => {
  it('skips the summary after an immediate cancel but celebrates arrivals', () => {
    expect(journeySummaryKind(false, 0, 2000)).toBe('none');
    expect(journeySummaryKind(false, 2500, 30_000)).toBe('none');
    expect(journeySummaryKind(false, 2500, 600_000)).toBe('ended');
    expect(journeySummaryKind(true, 0, 1000)).toBe('arrived');
  });

  it('only changes layout signature on rotation or breakpoint changes', () => {
    expect(layoutSignature(390, 844)).toBe(layoutSignature(390, 500));
    expect(layoutSignature(390, 844)).not.toBe(layoutSignature(844, 390));
    expect(layoutSignature(700, 900)).not.toBe(layoutSignature(800, 900));
  });
});
