import { t, type Language } from './i18n';
import { parseRetryAfter } from './api';
export type { Language } from './i18n';
export type RecentDestination = { label: string; latitude: number; longitude: number };
export type SavedPlace = {
  placeId: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  isFavorite: boolean;
  note: string;
  updatedAt: number;
};
export type RouteHistory = { id: string; destinationName: string; latitude: number; longitude: number; mode: string; distanceMeters: number | null; durationSeconds: number | null; startedAt: number };
export type OwnReview = { placeId: string; placeName: string; rating: number; comment: string; updatedAt: number };
export type AccountProfile = {
  user: { id: string; email: string };
  language: Language;
  voiceEnabled: boolean;
  recentDestinations: RecentDestination[];
  savedPlaces: SavedPlace[];
  routeHistory: RouteHistory[];
  reviews: OwnReview[];
};

class AccountError extends Error {
  constructor(message: string, readonly status: number, readonly code: unknown, readonly retryAfterMs: number | null) { super(message); }
}

/**
 * What to tell the user about a failed account request: rate limits and
 * lockouts get a localised wait time, server errors (generic 5xx bodies) a
 * localised message; only 4xx validation messages are shown as sent.
 */
export function accountErrorMessage(error: unknown, language: Language) {
  if (error instanceof AccountError) {
    if (error.status === 429) {
      const minutes = Math.max(1, Math.ceil((error.retryAfterMs ?? 60_000) / 60_000));
      return t(language, error.code === 'LOGIN_LOCKED' ? 'accountLocked' : 'accountRateLimited', { minutes });
    }
    if (error.status >= 500) return t(language, 'accountError');
    return error.message || t(language, 'accountError');
  }
  return t(language, 'accountError');
}

let profile: AccountProfile | null = null;
let mode: 'code' | 'password' = 'code';
let challenge: { email: string; id: string; resendAt: number } | null = null;
let accountBusy = false;
let accountRoot: HTMLElement;
let getLanguage: () => Language;
let getVoiceEnabled: () => boolean;
let onProfileLoaded: (next: AccountProfile) => void;

async function accountApi<T>(path: string, method = 'GET', body?: object): Promise<T> {
  const response = await fetch(path, {
    method,
    credentials: 'same-origin',
    headers: method === 'GET' ? {} : { 'content-type': 'application/json', 'x-waybi-client': 'web' },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(12_000)
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new AccountError(data.error || `HTTP ${response.status}`, response.status, data.code, parseRetryAfter(response.headers.get('retry-after')));
  return data as T;
}

export function isSignedIn() { return Boolean(profile); }
export function currentProfile() { return profile; }
export function ownReview(placeId: string) { return profile?.reviews?.find((review) => review.placeId === placeId) || null; }
export function currentAccountEmail() { return profile?.user.email || ''; }
export function recentDestinations() { return profile?.recentDestinations || []; }
export function savedPlace(placeId: string) {
  return profile?.savedPlaces?.find((place) => place.placeId === placeId) || null;
}

export function renderAccount() {
  if (!accountRoot) return;
  const language = getLanguage();
  const text = (key: Parameters<typeof t>[1], params?: Record<string, string | number>) => t(language, key, params);
  accountRoot.replaceChildren();
  const heading = document.createElement('h3');
  heading.textContent = text('accountTitle');
  accountRoot.append(heading);
  if (profile) {
    const signedIn = document.createElement('p');
    signedIn.className = 'account-note';
    signedIn.textContent = text('accountSignedIn', { email: profile.user.email });
    const signOut = document.createElement('button');
    signOut.type = 'button';
    signOut.className = 'account-button secondary';
    signOut.textContent = text('accountLogout');
    signOut.onclick = async () => {
      try { await accountApi('/api/auth/logout', 'POST'); } catch { /* clear client session anyway */ }
      profile = null;
      renderAccount();
      window.dispatchEvent(new Event('kiwi-account-change'));
    };
    accountRoot.append(signedIn, signOut);
    return;
  }
  const guest = document.createElement('p');
  guest.className = 'account-note';
  guest.textContent = text('accountGuest');
  const form = document.createElement('form');
  form.className = 'account-form';
  const email = document.createElement('input');
  email.type = 'email';
  email.required = true;
  email.autocomplete = 'email';
  email.placeholder = text('accountEmail');
  email.setAttribute('aria-label', text('accountEmail'));
  const zh = language === 'zh';
  if (challenge) email.value = challenge.email;
  email.readOnly = Boolean(challenge);
  const credential = document.createElement('input');
  credential.type = mode === 'password' ? 'password' : 'text';
  credential.required = true;
  credential.autocomplete = mode === 'password' ? 'current-password' : 'one-time-code';
  credential.placeholder = mode === 'password' ? text('accountPassword') : text('accountCode');
  credential.setAttribute('aria-label', credential.placeholder);
  if (mode === 'code') { credential.inputMode = 'numeric'; credential.pattern = '[0-9]{6}'; credential.maxLength = 6; }
  const submit = document.createElement('button');
  submit.className = 'account-button';
  submit.type = 'submit';
  submit.textContent = mode === 'password' ? text('accountLogin') : challenge ? text('accountVerify') : text('accountContinueEmail');
  const status = document.createElement('span');
  status.className = 'account-error';
  status.setAttribute('role', 'status');
  form.append(email);
  if (mode === 'password' || challenge) form.append(credential);
  form.append(submit, status);
  form.onsubmit = async (event) => {
    event.preventDefault();
    if (accountBusy || !form.reportValidity()) return;
    accountBusy = true;
    submit.disabled = true;
    email.disabled = true;
    credential.disabled = true;
    switchMode.disabled = true;
    form.setAttribute('aria-busy', 'true');
    status.textContent = '';
    try {
      if (mode === 'code' && !challenge) {
        const sent = await accountApi<{challengeId: string; retryAfter: number}>('/api/auth/email/request', 'POST', {email: email.value.trim(), language: getLanguage()});
        challenge = {email: email.value.trim(), id: sent.challengeId, resendAt: Date.now() + sent.retryAfter * 1000};
        renderAccount();
        accountRoot.querySelector<HTMLInputElement>('input[autocomplete=one-time-code]')?.focus();
        return;
      }
      const next = await accountApi<AccountProfile>(mode === 'password' ? '/api/auth/login' : '/api/auth/email/verify', 'POST', {
        email: email.value,
        ...(mode === 'password' ? {password: credential.value} : {challengeId: challenge!.id, code: credential.value}),
        language: getLanguage(),
        voiceEnabled: getVoiceEnabled()
      });
      profile = next;
      credential.value = '';
      challenge = null;
      onProfileLoaded(next);
      renderAccount();
      window.dispatchEvent(new Event('kiwi-account-change'));
    } catch (error) {
      status.textContent = accountErrorMessage(error, language);
      submit.disabled = false;
    } finally {
      accountBusy = false;
      email.disabled = false;
      credential.disabled = false;
      switchMode.disabled = false;
      form.removeAttribute('aria-busy');
    }
  };
  const switchMode = document.createElement('button');
  switchMode.type = 'button';
  switchMode.className = 'account-link';
  switchMode.textContent = mode === 'code' ? text('accountUsePassword') : text('accountUseCode');
  switchMode.onclick = () => { if (accountBusy) return; mode = mode === 'code' ? 'password' : 'code'; challenge = null; renderAccount(); };
  const warning = document.createElement('p');
  warning.className = 'account-warning';
  warning.textContent = text('accountWarning');
  accountRoot.append(guest, form, switchMode, warning);
  if (challenge) {
    const note = document.createElement('p'); note.className = 'account-note';
    note.textContent = text('accountCheckInbox');
    form.before(note);
    const resend = document.createElement('button'); resend.type = 'button'; resend.className = 'account-link';
    resend.textContent = text('accountResend');
    const changeEmail = document.createElement('button'); changeEmail.type = 'button'; changeEmail.className = 'account-link';
    changeEmail.textContent = text('accountChangeEmail');
    changeEmail.onclick = () => { if (!accountBusy) { challenge = null; renderAccount(); } };
    resend.onclick = async () => {
      if (accountBusy || !challenge) return;
      const remaining = Math.ceil((challenge.resendAt - Date.now()) / 1000);
      if (remaining > 0) { status.textContent = text('accountRetryIn', { seconds: remaining }); return; }
      accountBusy = true; resend.disabled = true; submit.disabled = true;
      try {
        const sent = await accountApi<{challengeId: string; retryAfter: number}>('/api/auth/email/request', 'POST', {email: challenge.email, language: getLanguage()});
        challenge = {...challenge, id: sent.challengeId, resendAt: Date.now() + sent.retryAfter * 1000};
        credential.value = ''; status.textContent = text('accountCodeSent');
      } catch (error) { status.textContent = accountErrorMessage(error, language); }
      finally { accountBusy = false; resend.disabled = false; submit.disabled = false; }
    };
    accountRoot.append(resend, document.createTextNode(' · '), changeEmail);
  }
  const policies = document.createElement('p'); policies.className = 'account-note account-policies';
  for (const [page, label] of [['terms', text('accountTerms')], ['privacy', text('accountPrivacy')]] as const) {
    const link = document.createElement('a'); link.href = `${zh ? '/zh' : ''}/${page}/`; link.textContent = label;
    link.target = '_blank'; link.rel = 'noopener'; policies.append(link, document.createTextNode(' '));
  }
  accountRoot.append(policies);
}

export async function initAccount(root: HTMLElement, language: () => Language, voice: () => boolean,
  onLoaded: (next: AccountProfile) => void) {
  accountRoot = root;
  getLanguage = language;
  getVoiceEnabled = voice;
  onProfileLoaded = onLoaded;
  renderAccount();
  try {
    profile = await accountApi<AccountProfile>('/api/auth/me');
    onProfileLoaded(profile);
    renderAccount();
  } catch { /* guest mode is always usable */ }
}

export async function rememberPreferences(language: Language, voiceEnabled: boolean) {
  if (!profile) return;
  try {
    profile = await accountApi<AccountProfile>('/api/profile', 'PATCH', { language, voiceEnabled });
  } catch { /* do not block navigation when account storage is unavailable */ }
}

export async function rememberDestination(destination: RecentDestination) {
  if (!profile) return;
  try {
    profile = await accountApi<AccountProfile>('/api/profile/destinations', 'POST', destination);
  } catch { /* the route remains usable without persistence */ }
}

export async function savePlace(input: {
  placeId: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  isFavorite: boolean;
  note: string;
}) {
  if (!profile) throw new Error('Sign in to save places');
  profile = await accountApi<AccountProfile>('/api/profile/places', 'POST', input);
  return savedPlace(input.placeId);
}

export async function rememberRoute(input: {
  destinationName: string; latitude: number; longitude: number; mode: string;
  distanceMeters: number | null; durationSeconds: number | null;
}) {
  if (!profile) return;
  profile = await accountApi<AccountProfile>('/api/profile/routes', 'POST', input);
  window.dispatchEvent(new Event('kiwi-account-change'));
}

export async function saveOwnReview(input: {
  placeId: string; placeName: string; rating: number; comment: string;
}) {
  if (!profile) throw new Error('Sign in to save your review');
  profile = await accountApi<AccountProfile>('/api/profile/reviews', 'POST', input);
  window.dispatchEvent(new Event('kiwi-account-change'));
  return ownReview(input.placeId);
}
