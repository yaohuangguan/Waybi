/**
 * Coordinates route-planning requests so that GPS fixes, reroutes and user
 * actions do not abort each other in a loop, and so failures back off instead
 * of hammering the routing API (and the user with toasts).
 */
export type PlanTrigger = 'user' | 'auto' | 'reroute';

export class Backoff {
  failures = 0;
  private nextAt = 0;
  constructor(private readonly baseMs = 2_000, private readonly maxMs = 60_000) {}
  /** Records a failure and returns the delay before the next automatic attempt. */
  fail(now = Date.now(), retryAfterMs?: number | null) {
    this.failures += 1;
    const exponential = Math.min(this.maxMs, this.baseMs * 2 ** (this.failures - 1));
    const delay = Math.max(exponential, retryAfterMs ?? 0);
    this.nextAt = now + delay;
    return delay;
  }
  succeed() { this.failures = 0; this.nextAt = 0; }
  ready(now = Date.now()) { return now >= this.nextAt; }
  remaining(now = Date.now()) { return Math.max(0, this.nextAt - now); }
}

export class RouteRequestCoordinator {
  readonly backoff: Backoff;
  private controller: AbortController | null = null;
  private trigger: PlanTrigger | null = null;
  private failureNotified = false;

  constructor(backoff = new Backoff()) { this.backoff = backoff; }

  get pending() { return this.controller !== null; }
  get pendingTrigger() { return this.trigger; }

  /**
   * Automatic plans (from a GPS fix or an off-route check) never replace a
   * request that is already in flight and wait for the failure backoff.
   * A user action always starts a fresh request.
   */
  canStart(trigger: PlanTrigger, now = Date.now()) {
    if (trigger === 'user') return true;
    return !this.controller && this.backoff.ready(now);
  }

  begin(trigger: PlanTrigger): AbortController {
    this.controller?.abort();
    this.controller = new AbortController();
    this.trigger = trigger;
    if (trigger === 'user') this.failureNotified = false;
    return this.controller;
  }

  /** True when `controller` is still the current request. */
  isCurrent(controller: AbortController) { return this.controller === controller; }

  succeed(controller: AbortController) {
    if (!this.isCurrent(controller)) return;
    this.controller = null;
    this.trigger = null;
    this.failureNotified = false;
    this.backoff.succeed();
  }

  /**
   * Records a failed request. Returns the backoff delay and whether this is
   * the first failure of a streak (the only one worth telling the user about).
   */
  fail(controller: AbortController, retryAfterMs?: number | null, now = Date.now()) {
    if (this.isCurrent(controller)) { this.controller = null; this.trigger = null; }
    const delay = this.backoff.fail(now, retryAfterMs);
    const notify = !this.failureNotified;
    this.failureNotified = true;
    return { delay, notify };
  }

  /** Cancels any request in flight (destination cleared, navigation ended…). */
  cancel() {
    this.controller?.abort();
    this.controller = null;
    this.trigger = null;
  }

  reset() {
    this.cancel();
    this.backoff.succeed();
    this.failureNotified = false;
  }
}

export type JourneySummaryKind = 'arrived' | 'ended' | 'none';

/**
 * Ending navigation straight after starting should not celebrate a
 * "Journey complete · 0 m": only arrivals and real trips get a summary.
 */
export function journeySummaryKind(arrived: boolean, travelledMeters: number, elapsedMs: number): JourneySummaryKind {
  if (arrived) return 'arrived';
  if (travelledMeters < 100 || elapsedMs < 60_000) return 'none';
  return 'ended';
}

/** Re-fit the route only when the layout really changes (rotation or crossing the desktop breakpoint). */
export function layoutSignature(width: number, height: number, breakpoint = 760) {
  return `${width >= breakpoint ? 'wide' : 'narrow'}:${width > height ? 'landscape' : 'portrait'}`;
}
