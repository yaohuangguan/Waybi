// Existing installed clients keep working during the Waybi identity rollout.
export function clientKind(request) {
  return request.headers.get('x-waybi-client') || request.headers.get('x-kiwi-client');
}
export function sessionCookieName(request) {
  return request.headers.has('x-kiwi-client') && !request.headers.has('x-waybi-client') ? 'kiwi_session' : 'waybi_session';
}
