/** Errors whose message is safe to show to API clients. Anything else is
 * logged with a request id and answered with a generic message, so D1 table
 * names, provider responses and stack traces never reach a client. */
export class HttpError extends Error {
  readonly status: number;
  readonly code?: string;
  readonly headers: Record<string, string>;
  constructor(status: number, publicMessage: string, options: { code?: string; headers?: Record<string, string>; cause?: unknown } = {}) {
    super(publicMessage, options.cause === undefined ? undefined : { cause: options.cause });
    this.name = 'HttpError';
    this.status = status;
    this.code = options.code;
    this.headers = options.headers || {};
  }
}

/** A provider outage or malformed provider payload. Clients see a generic 502. */
export class UpstreamError extends Error {
  constructor(message: string, options: { cause?: unknown } = {}) {
    super(message, options.cause === undefined ? undefined : { cause: options.cause });
    this.name = 'UpstreamError';
  }
}

function upstreamFailure(error: unknown): boolean {
  if (error instanceof UpstreamError) return true;
  const name = (error as { name?: string })?.name;
  if (name === 'TimeoutError' || name === 'AbortError') return true;
  // Runtime network failures only; a TypeError from our own code stays a 500.
  return error instanceof TypeError && /fetch failed|failed to fetch|network connection|connection (?:lost|refused|reset)/i.test(String((error as Error).message || ''));
}

export function classifyError(error: unknown): { status: number; message: string; code?: string; headers: Record<string, string> } {
  if (error instanceof HttpError) {
    return { status: error.status, message: error.message, code: error.code, headers: error.headers };
  }
  // decodeURIComponent on a malformed path segment is a client error.
  if (error instanceof URIError) return { status: 400, message: 'Invalid request encoding', code: 'INVALID_REQUEST', headers: {} };
  if (upstreamFailure(error)) return { status: 502, message: 'Upstream service unavailable. Please retry shortly.', code: 'UPSTREAM_UNAVAILABLE', headers: {} };
  return { status: 500, message: 'Internal error', code: 'INTERNAL_ERROR', headers: {} };
}

/** One structured log line per failed API request, without query strings
 * (which can contain coordinates or email addresses) or credentials. */
export function logRequestError(error: unknown, request: Request, requestId: string, status: number) {
  const url = new URL(request.url);
  const entry = {
    level: status >= 500 ? 'error' : 'warn',
    event: 'api_error',
    requestId,
    cfRay: request.headers.get('cf-ray') || null,
    method: request.method,
    path: url.pathname.slice(0, 200),
    status,
    errorName: (error as Error)?.name || typeof error,
    message: String((error as Error)?.message || error).slice(0, 300),
  };
  if (status >= 500) console.error(JSON.stringify(entry));
  else console.warn(JSON.stringify(entry));
}

export function apiErrorResponse(error: unknown, request: Request, requestId: string): Response {
  const { status, message, code, headers } = classifyError(error);
  logRequestError(error, request, requestId, status);
  return new Response(JSON.stringify({ error: message, ...(code ? { code } : {}), requestId }), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'access-control-allow-origin': '*',
      'x-request-id': requestId,
      ...headers,
    },
  });
}
